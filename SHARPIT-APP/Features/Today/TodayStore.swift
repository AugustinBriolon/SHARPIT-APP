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

    private let client: any TodayServing
    private let tokenProvider: (() async throws -> String)?
    private let modelContext: ModelContext?

    init(
        client: any TodayServing = FixtureTodayClient(),
        tokenProvider: (() async throws -> String)? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
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

    var loadedPosture: V1TodayPosture? {
        if case .loaded(let fold) = phase { return fold.plate.posture }
        return nil
    }

    var navigationTitle: String {
        if case .loaded(let fold) = phase {
            return TrainingDayId.displayName(fold.trainingDayId)
        }
        return "Résumé"
    }

    func load(resetToLoading: Bool) async {
        let dayId = TrainingDayId.today()
        let hadCache = hydrateFromSnapshotIfNeeded(dayId: dayId, resetToLoading: resetToLoading)

        do {
            let token: String
            if let tokenProvider {
                token = try await tokenProvider()
            } else {
                token = ""
            }
            let payload = try await client.today(trainingDayId: dayId, token: token)
            apply(payload)
            persistSnapshot(payload)
        } catch is CancellationError {
            return
        } catch let error as SharpitAPIError where error == .unauthorized {
            phase = .unauthorized
        } catch {
            // Keep stale snapshot on transport failure when we already painted it.
            if hadCache, case .loaded = phase {
                return
            }
            if case .loaded = phase {
                return
            }
            phase = .failed(Self.failureMessage(for: error))
        }
    }

    func refresh() async {
        await load(resetToLoading: false)
        if case .loaded(let fold) = phase {
            SharpitHaptics.play(.light)
            flashScores()
            markNewSessionDones(in: fold)
        }
    }

    func handleArrivalWins(fold: TodayFold) {
        let key = SharpitWinStore.arrivalKey(trainingDayId: fold.trainingDayId)
        if SharpitWinStore.consume(key) {
            SharpitHaptics.play(.soft)
        }
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
                apply(cached)
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

    private func apply(_ payload: V1TodayResponse) {
        switch TodayModel.state(from: payload) {
        case .loading:
            phase = .loading
        case .loaded(let response):
            phase = .loaded(TodayFoldMapper.map(response))
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
        do {
            try TodaySnapshotRepository.save(payload, context: modelContext)
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
            return "Réseau indisponible — vérifie yarn dev sur 127.0.0.1:3000"
        case .unauthorized:
            return "Session expirée"
        }
    }
}
