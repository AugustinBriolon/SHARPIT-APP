import Foundation
import Observation
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

    init(
        client: any TodayServing = FixtureTodayClient(),
        tokenProvider: (() async throws -> String)? = nil
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
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
        if resetToLoading {
            phase = .loading
        }
        do {
            let token: String
            if let tokenProvider {
                token = try await tokenProvider()
            } else {
                token = ""
            }
            let payload = try await client.today(trainingDayId: TrainingDayId.today(), token: token)
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
        } catch is CancellationError {
            return
        } catch let error as SharpitAPIError where error == .unauthorized {
            phase = .unauthorized
        } catch {
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
