import Foundation
import Observation

/// Today's food log for the Résumé card. The log is the athlete's own data, open to all; the
/// server says whether one is connected and the card reflects the answer.
@MainActor
@Observable
final class NutritionTodayStore {
    enum Phase: Equatable {
        case loading
        /// No food log connected.
        case disconnected
        /// Connected, nothing logged yet today.
        case empty
        case loaded(V1NutritionDay)
        /// The read failed: the card says so quietly and opens the day, which can retry.
        case failed
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
            WidgetSnapshotPublisher.publish(nutrition)
        } catch is CancellationError {
        } catch {
            // Keep a day already on screen; only a first read that fails says so.
            if case .loaded = phase { return }
            phase = .failed
        }
    }

    static func phase(for nutrition: V1NutritionResponse) -> Phase {
        guard nutrition.connected else { return .disconnected }
        guard let day = nutrition.day else { return .empty }
        return .loaded(day)
    }
}
