import Foundation
import Observation

/// Today's food log for the Résumé card. The server decides who may read it (SharpIt Pro)
/// and whether a log is connected; the card only reflects the answer.
@MainActor
@Observable
final class NutritionTodayStore {
    enum Phase: Equatable {
        case loading
        /// Below SharpIt Pro: the card offers Pro instead.
        case locked
        /// No food log connected.
        case disconnected
        /// Connected, nothing logged yet today.
        case empty
        case loaded(V1NutritionDay)
        /// A failed read: a Résumé card stays out of the way rather than showing an error.
        case hidden
    }

    private(set) var phase: Phase = .loading

    private let client: any NutritionServing
    private let tokenProvider: () async throws -> String

    init(client: any NutritionServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func load(trainingDayId: String) async {
        do {
            let token = try await tokenProvider()
            let nutrition = try await client.nutrition(trainingDayId: trainingDayId, token: token)
            phase = Self.phase(for: nutrition)
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .proRequired {
            phase = .locked
        } catch {
            // Keep a day already on screen; only a first read that fails hides the card.
            if case .loaded = phase { return }
            phase = .hidden
        }
    }

    static func phase(for nutrition: V1NutritionResponse) -> Phase {
        guard nutrition.connected else { return .disconnected }
        guard let day = nutrition.day else { return .empty }
        return .loaded(day)
    }
}
