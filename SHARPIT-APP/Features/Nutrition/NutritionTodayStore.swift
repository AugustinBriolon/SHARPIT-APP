import Foundation
import Observation
import SwiftData

/// Today's food log for the Résumé card. The log is the athlete's own data, open to all, and
/// lives in SHARPIT (ADR-061): there is no food log to connect, only a day to fill.
@MainActor
@Observable
final class NutritionTodayStore {
    enum Phase: Equatable {
        case loading
        /// Nothing logged yet today: the card invites to log a meal.
        case empty
        case loaded(V1NutritionDay)
        /// The read failed: the card says so quietly and opens the day, which can retry.
        case failed
    }

    private(set) var phase: Phase = .loading

    private let client: any NutritionServing
    private let tokenProvider: () async throws -> String
    private let modelContext: ModelContext?
    /// The day last asked for, so the fold's own read does not ask again for a day Résumé
    /// already started reading alongside today.
    private var requestedDayId: String?

    init(
        client: any NutritionServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
    }

    /// Reads the day unless it is already read or being read.
    func loadIfNeeded(trainingDayId: String) async {
        guard requestedDayId != trainingDayId else { return }
        await load(trainingDayId: trainingDayId)
    }

    func load(trainingDayId: String) async {
        // The card paints the last answer for the day while the server answers, as the rest of
        // Résumé paints from its snapshot: without it, it was the one card still redacted.
        if requestedDayId != trainingDayId {
            requestedDayId = trainingDayId
            if let cached = ResponseCache.read(
                CachedDay.self,
                key: ResponseCacheKey.nutritionDay(trainingDayId),
                context: modelContext
            ) {
                phase = cached.day.map(Phase.loaded) ?? .empty
            }
        }
        do {
            let token = try await tokenProvider()
            let nutrition = try await client.nutrition(trainingDayId: trainingDayId, token: token)
            guard requestedDayId == trainingDayId else { return }
            phase = Self.phase(for: nutrition)
            ResponseCache.write(
                CachedDay(day: nutrition.day),
                key: ResponseCacheKey.nutritionDay(trainingDayId),
                context: modelContext
            )
            WidgetSnapshotPublisher.publish(nutrition)
        } catch is CancellationError {
        } catch {
            // Keep a day already on screen; only a first read that fails says so.
            if case .loaded = phase { return }
            phase = .failed
        }
    }

    static func phase(for nutrition: V1NutritionResponse) -> Phase {
        nutrition.day.map(Phase.loaded) ?? .empty
    }

    /// What the card needs from the answer: the day, or nothing logged.
    private struct CachedDay: Codable {
        let day: V1NutritionDay?
    }
}
