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
    /// A past day the athlete opened from the title; nil follows today, midnight included.
    private(set) var selectedDayId: String?

    var dayId: String { selectedDayId ?? TrainingDayId.today() }
    var isToday: Bool { selectedDayId == nil }

    func markArrivalCompleted() {
        hasCompletedArrival = true
    }

    private let client: any TodayServing
    private let proposals: any MorningProposalServing
    private let tokenProvider: (() async throws -> String)?
    private let modelContext: ModelContext?
    private let dayReads: DayReadCache
    /// Folds already mapped for the page drawn beside this one while a swipe moves it.
    @ObservationIgnored private var neighborFolds: [String: TodayFold] = [:]
    /// Tab `.task` re-fires on every return; skip the network while the day is still fresh.
    private let networkGate = LoadGate()

    init(
        client: any TodayServing = FixtureTodayClient(),
        proposals: any MorningProposalServing = SharpitClient(),
        tokenProvider: (() async throws -> String)? = nil,
        modelContext: ModelContext? = nil,
        dayReads: DayReadCache = .shared
    ) {
        self.client = client
        self.proposals = proposals
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
        self.dayReads = dayReads
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
        if case .loading = phase, selectedDayId == nil { return String(localized: "Résumé") }
        // The day asked for, at once, even while the one before is still on screen.
        return TrainingDayId.displayName(dayId)
    }

    /// Reads another day; today's date goes back to following today.
    func select(day: Date) async {
        let picked = TrainingDayId.today(now: day)
        let next = picked == TrainingDayId.today() ? nil : picked
        guard next != selectedDayId else { return }
        selectedDayId = next
        // The day on screen stays until the new one arrives, so the page never blanks.
        await load(resetToLoading: false, force: true)
    }

    func load(resetToLoading: Bool, force: Bool = false) async {
        let dayId = self.dayId
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

        await networkGate.run(key: dayId, force: force) {
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
        dayReads.keep(payload, day: dayId)
        neighborFolds[dayId] = nil
        // A late answer for a day left since must not replace the one now asked for.
        guard dayId == self.dayId else { return false }
        apply(payload, animated: true)
        persistSnapshot(payload)
        Task { await prefetchNeighbors(token: token) }
        return true
    }

    /// A day already read, as the page drawn beside this one while a swipe moves it.
    func knownFold(on day: Date) -> TodayFold? {
        let dayId = TrainingDayId.today(now: day)
        if let fold = neighborFolds[dayId] { return fold }
        guard let payload = dayReads.lastKnown(V1TodayResponse.self, day: dayId),
              case .loaded(let response) = TodayModel.state(from: payload)
        else { return nil }
        let fold = TodayFoldMapper.map(response)
        neighborFolds[dayId] = fold
        return fold
    }

    /// Reads the days on either side of the one shown, so a swipe brings in a filled page.
    private func prefetchNeighbors(token: String) async {
        guard let shown = TrainingDayId.date(dayId) else { return }
        for step in [DaySwipe.Step.previous, .next] {
            guard let day = DaySwipe.day(after: step, from: shown) else { continue }
            let dayId = TrainingDayId.today(now: day)
            guard dayReads.lastKnown(V1TodayResponse.self, day: dayId) == nil,
                  let payload = try? await client.today(trainingDayId: dayId, token: token)
            else { continue }
            dayReads.keep(payload, day: dayId)
        }
    }

    private func keepOrFail(hadCache: Bool, error: Error) -> Bool {
        if hadCache, case .loaded = phase { return false }
        if case .loaded = phase { return false }
        phase = .failed(Self.failureMessage(for: error))
        return false
    }

    func refresh() async {
        dayReads.expire(day: dayId)
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
        // Tab `.task` re-enters load while the rich in-memory fold is still here. The disk
        // snapshot is glossary-only (plate, no sessions/gauges): never overwrite a live day
        // with that stub or the résumé blanks until pull-to-refresh forces the network.
        if case .loaded(let fold) = phase, fold.trainingDayId == dayId {
            return true
        }
        // The day as last read this launch, whole, while the network reads it again.
        if let known = dayReads.lastKnown(V1TodayResponse.self, day: dayId) {
            apply(known)
            if case .loaded = phase { return true }
        }
        guard let modelContext else {
            if resetToLoading { phase = .loading }
            return false
        }
        do {
            if let cached = try TodaySnapshotRepository.load(trainingDayId: dayId, context: modelContext) {
                // Cold start / empty phase: paint the plate first, then network fills the rest.
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
            // A past day opened from the title is not what the widgets show.
            if fold.trainingDayId == TrainingDayId.today() {
                WidgetSnapshotPublisher.publish(fold)
            }
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
        return String(localized: "Réponse non enregistrée. Réessaie dans un instant.")
    }

    private static func failureMessage(for error: Error) -> String {
        guard let apiError = error as? SharpitAPIError else {
            return String(localized: "Impossible de charger le résumé")
        }
        switch apiError {
        case .badRequest, .conflict:
            return String(localized: "Requête invalide")
        case .server:
            return String(localized: "Le serveur n'a pas pu produire le résumé")
        case .transport:
            return String(localized: "Réseau indisponible")
        case .unauthorized:
            return String(localized: "Session expirée")
        case .rateLimited:
            return String(localized: "Trop de requêtes — réessaie dans un instant")
        case .message(let text), .googleNeedsReconnect(let text):
            return text
        case .proRequired:
            return apiError.errorDescription ?? ""
        }
    }
}
