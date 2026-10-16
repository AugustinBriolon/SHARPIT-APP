import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class TodayStore {
    enum Phase: Equatable {
        case loading
        case loaded(TodayFold)
        case empty(V1TodayEmpty)
        case failed(String)
        case unauthorized
    }

    var phase: Phase = .loading
    var pulseScores = false
    var sessionDoneCelebrations: Set<String> = []
    var hasCompletedArrival = false

    func markArrivalCompleted() {
        hasCompletedArrival = true
    }

    private let client: any TodayServing
    private let proposals: any MorningProposalServing
    private let tokenProvider: (() async throws -> String)?
    private let modelContext: ModelContext?
    /// Tab `.task` re-fires on every return; skip the network while the day is still fresh.
    private let networkGate = LoadGate()

    init(
        client: any TodayServing = FixtureTodayClient(),
        proposals: any MorningProposalServing = SharpitClient(),
        tokenProvider: (() async throws -> String)? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.client = client
        self.proposals = proposals
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
    }

    /// Answers the night's proposal. The card leaves on the tap; it comes back with the failure
    /// said if the server refuses. Accepted, the day is read again: the session changed.
    /// Returns whether the plan changed.
    @discardableResult
    func respondToMorningProposal(accept: Bool) async -> Bool {
        guard case .loaded(var fold) = phase, let proposal = fold.morningProposal else { return false }
        guard let tokenProvider else { return false }
        fold.morningProposal = nil
        phase = .loaded(fold)
        do {
            try await SharpitRetry.run {
                try await self.proposals.respondToMorningProposal(
                    decisionId: proposal.decisionId,
                    accept: accept,
                    token: try await tokenProvider()
                )
            }
        } catch {
            if case .loaded(var current) = phase, current.morningProposal == nil {
                current.morningProposal = proposal
                phase = .loaded(current)
            }
            SharpitWriteFailures.shared.report(Self.proposalFailureMessage(for: error))
            return false
        }
        if accept {
            await load(resetToLoading: false, force: true)
        }
        return accept
    }

    var phaseIdentity: String {
        switch phase {
        case .loading: "loading"
        case .loaded: "loaded"
        case .empty: "empty"
        case .failed: "failed"
        case .unauthorized: "unauthorized"
        }
    }

    var navigationTitle: String {
        if case .loaded(let fold) = phase {
            return TrainingDayId.displayName(fold.trainingDayId)
        }
        return "Résumé"
    }

    func load(resetToLoading: Bool, force: Bool = false) async {
        let dayId = TrainingDayId.today()
        let hadCache = hydrateFromSnapshotIfNeeded(dayId: dayId, resetToLoading: resetToLoading)

        // Never send `Authorization: Bearer ` with an empty token. Without a provider the
        // store stays fixture-only (previews / offline demos).
        guard let tokenProvider else {
            do {
                let payload = try await client.today(trainingDayId: dayId, token: "fixture")
                apply(payload)
                persistSnapshot(payload)
            } catch {
                if hadCache, case .loaded = phase { return }
                if case .loaded = phase { return }
                phase = .failed(Self.failureMessage(for: error))
            }
            return
        }

        await networkGate.run(force: force) {
            await self.fetchToday(dayId: dayId, tokenProvider: tokenProvider, hadCache: hadCache)
        }
    }

    /// One network read; on 401 refresh the Clerk token once and retry before purging.
    private func fetchToday(
        dayId: String,
        tokenProvider: @escaping () async throws -> String,
        hadCache: Bool
    ) async -> Bool {
        do {
            let token = try await tokenProvider()
            return try await applyNetworkToday(dayId: dayId, token: token)
        } catch is CancellationError {
            return false
        } catch let error as SharpitAPIError where error == .unauthorized {
            if let refreshed = await AuthSession.shared.refreshTokenOnce() {
                do {
                    return try await applyNetworkToday(dayId: dayId, token: refreshed)
                } catch let error as SharpitAPIError where error == .unauthorized {
                    await AuthSession.shared.expireSession()
                    phase = .unauthorized
                    return false
                } catch {
                    return keepOrFail(hadCache: hadCache, error: error)
                }
            }
            await AuthSession.shared.expireSession()
            phase = .unauthorized
            return false
        } catch {
            return keepOrFail(hadCache: hadCache, error: error)
        }
    }

    private func applyNetworkToday(dayId: String, token: String) async throws -> Bool {
        let payload = try await client.today(trainingDayId: dayId, token: token)
        apply(payload, animated: true)
        persistSnapshot(payload)
        return true
    }

    private func keepOrFail(hadCache: Bool, error: Error) -> Bool {
        if hadCache, case .loaded = phase { return false }
        if case .loaded = phase { return false }
        phase = .failed(Self.failureMessage(for: error))
        return false
    }

    func refresh() async {
        await load(resetToLoading: false, force: true)
        if case .loaded(let fold) = phase {
            flashScores()
            markNewSessionDones(in: fold)
        }
    }

    func handleArrivalWins(fold: TodayFold) {
        markNewSessionDones(in: fold)
        if let confidence = fold.plate.confidencePct {
            SharpitWinStore.setLastConfidence(confidence, trainingDayId: fold.trainingDayId)
        }
    }

    @discardableResult
    private func hydrateFromSnapshotIfNeeded(dayId: String, resetToLoading: Bool) -> Bool {
        guard let modelContext else {
            if resetToLoading { phase = .loading }
            return false
        }
        do {
            if let cached = try TodaySnapshotRepository.load(trainingDayId: dayId, context: modelContext) {
                // Today's glossary plate only — no layout jump to a blank loading screen.
                phase = .loaded(cached.asFold())
                return true
            }
        } catch {
            // Corrupt cache — fall through to network / loading.
        }
        if resetToLoading {
            phase = .loading
        }
        return false
    }

    private func apply(_ payload: V1TodayResponse, animated: Bool = false) {
        switch TodayModel.state(from: payload) {
        case .loading:
            phase = .loading
        case .loaded(let response):
            let fold = TodayFoldMapper.map(response)
            if animated {
                SharpitMotion.run(SharpitMotion.fade) { phase = .loaded(fold) }
            } else {
                phase = .loaded(fold)
            }
            WidgetSnapshotPublisher.publish(fold)
        case .empty(let empty):
            phase = .empty(empty)
        case .failed(let message):
            phase = .failed(message)
        case .unauthorized:
            phase = .unauthorized
        }
    }

    private func persistSnapshot(_ payload: V1TodayResponse) {
        guard let modelContext else { return }
        let fold = TodayFoldMapper.map(payload)
        do {
            try TodaySnapshotRepository.save(fold, context: modelContext)
        } catch {
            // Persistence failure must not break the live fold.
        }
    }

    private func markNewSessionDones(in fold: TodayFold) {
        var fresh: Set<String> = []
        for session in fold.sessions where session.kind == .done {
            let doneKey = SharpitWinStore.sessionDoneKey(
                trainingDayId: fold.trainingDayId,
                sessionId: session.id
            )
            if SharpitWinStore.consume(doneKey) {
                fresh.insert(session.id)
            }
        }
        if !fresh.isEmpty {
            sessionDoneCelebrations.formUnion(fresh)
        }
    }

    private func flashScores() {
        SharpitMotion.run(.easeOut(duration: 0.18)) {
            pulseScores = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            SharpitMotion.run(.easeOut(duration: 0.22)) {
                pulseScores = false
            }
        }
    }

    /// The server's own refusal when it said why (« Cette proposition n’est plus en attente »).
    static func proposalFailureMessage(for error: Error) -> String {
        if case .message(let text)? = error as? SharpitAPIError { return text }
        if case .googleNeedsReconnect(let text)? = error as? SharpitAPIError { return text }
        return "Réponse non enregistrée. Réessaie dans un instant."
    }

    private static func failureMessage(for error: Error) -> String {
        guard let apiError = error as? SharpitAPIError else {
            return "Impossible de charger le résumé"
        }
        switch apiError {
        case .badRequest:
            return "Requête invalide"
        case .server:
            return "Le serveur n'a pas pu produire le résumé"
        case .transport:
            return "Réseau indisponible"
        case .unauthorized:
            return "Session expirée"
        case .rateLimited:
            return "Trop de requêtes — réessaie dans un instant"
        case .message(let text), .googleNeedsReconnect(let text):
            return text
        }
    }
}
