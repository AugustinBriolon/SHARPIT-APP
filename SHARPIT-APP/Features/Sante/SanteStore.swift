import Foundation
import Observation
import SwiftData

/// What Santé reads: the web's check-up (`/api/v1/health/overview`), kept whole so the page
/// paints at once, even offline, and refreshes behind (`docs/adr/0008`).
@MainActor
@Observable
final class SanteStore {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The web answered and nothing is measured yet.
        case empty
        case failed(String)
        case unauthorized
    }

    private(set) var phase: Phase = .loading
    private(set) var overview: V1HealthOverview?
    /// A refresh over a painted page failed; the page stays as it was.
    private(set) var refreshFailed = false
    /// « Aujourd'hui »: Energy Bank, stress, target band from the day Résumé also reads.
    private(set) var dayState: SanteDayState?

    private let client: any HealthOverviewServing
    private let todayClient: any TodayServing
    private let tokenProvider: () async throws -> String
    private let modelContext: ModelContext?

    init(
        client: any HealthOverviewServing = BodyClient(),
        todayClient: any TodayServing = SharpitClient(),
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        self.client = client
        self.todayClient = todayClient
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
        if let cached = ResponseCache.read(V1HealthOverview.self, key: ResponseCacheKey.healthOverview, context: modelContext) {
            adopt(cached)
        }
        // Day tiles need energy/stress/band — not in the glossary-only Today snapshot.
    }

    /// One GET /api/v1/today; glossary plate goes to the shared snapshot, tiles stay in memory.
    func loadDay() async {
        do {
            let day = try await todayClient.today(trainingDayId: TrainingDayId.today(), token: try await tokenProvider())
            if let modelContext {
                try? TodaySnapshotRepository.save(TodayFoldMapper.map(day), context: modelContext)
            }
            SharpitMotion.run { dayState = SanteDayState(day) }
        } catch {
            // The section is secondary to the check-up: no error state of its own.
        }
    }

    func load() async {
        do {
            let data = try await SharpitRetry.run {
                try await client.healthOverviewData(token: try await tokenProvider())
            }
            let fresh = try JSONDecoder().decode(V1HealthOverview.self, from: data)
            ResponseCache.write(data: data, key: ResponseCacheKey.healthOverview, context: modelContext)
            refreshFailed = false
            SharpitMotion.run { adopt(fresh) }
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            if overview == nil {
                phase = .failed("Lecture de ta santé impossible.")
            } else {
                refreshFailed = true
            }
        }
    }

    private func adopt(_ next: V1HealthOverview) {
        overview = next
        phase = next.isEmpty && next.synthesis.biologicalAge == nil ? .empty : .loaded
    }
}
