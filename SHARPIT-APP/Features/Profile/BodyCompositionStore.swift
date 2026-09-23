import Foundation
import Observation
import SwiftData

/// The weigh-ins behind Corps: the latest one, and what it moved from.
@MainActor
@Observable
final class BodyCompositionStore {
    enum Phase: Equatable {
        case idle
        case loading
        /// Loaded and empty — no scale has ever written. Distinct from a failure, because
        /// there is nothing to retry.
        case empty
        case loaded
        case failed(String)
        case unauthorized
    }

    /// Ninety days: long enough for a trend to mean something, short enough that a phone
    /// renders the list without paging.
    static let windowDays = 90

    private(set) var phase: Phase = .idle
    private(set) var measurements: [V1BodyMeasurement] = []
    /// The weight the athlete is aiming for, drawn across the trend. Nil when they never set
    /// one, which is most athletes: the chart then shows the line alone.
    private(set) var targetWeightKg: Double?
    /// Set when a refresh over a painted cache failed. The chart stays on screen either way.
    private(set) var refreshFailure: String?

    private let client: any BodyCompositionServing
    private let profileClient: (any AthleteProfileServing)?
    private let tokenProvider: () async throws -> String
    private let modelContext: ModelContext?

    init(
        client: any BodyCompositionServing,
        profileClient: (any AthleteProfileServing)? = nil,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        self.client = client
        self.profileClient = profileClient
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
    }

    /// Newest first, as the server orders them.
    var latest: V1BodyMeasurement? { measurements.first }

    /// The weigh-in a week or more before the latest, to read the current one against.
    ///
    /// Not simply the previous row: two weigh-ins on consecutive mornings differ by water,
    /// not by composition, and calling that a trend would invent a signal.
    var reference: V1BodyMeasurement? {
        guard let latest else { return nil }
        let cutoff = latest.measuredAt.addingTimeInterval(-7 * 24 * 3600)
        return measurements.first { $0.measuredAt <= cutoff }
    }

    /// The weigh-ins that carry a weight, oldest first, as a chart reads them.
    ///
    /// Reversed here rather than in the view: the server answers newest first because a list
    /// wants the latest at the top, and a time axis wants the opposite.
    var weightSeries: [BodyWeightPoint] {
        measurements
            .compactMap { measurement in
                guard let kilograms = measurement.weightKg, kilograms > 0 else { return nil }
                return BodyWeightPoint(day: measurement.measuredAt, kilograms: kilograms)
            }
            .reversed()
    }

    func load() async {
        guard phase != .loading else { return }
        let hadCache = hydrateFromCache()
        if !hadCache { phase = .loading }
        do {
            let token = try await tokenProvider()
            measurements = try await client.bodyComposition(days: Self.windowDays, token: token)
            phase = measurements.isEmpty ? .empty : .loaded
            refreshFailure = nil
            // After the weigh-ins, and never fatal: a missing target costs the chart its
            // dashed line, not its data.
            if let profileClient {
                targetWeightKg = (try? await profileClient.athleteProfile(token: token))?.targetWeightKg
            }
            persistCache()
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            if hadCache {
                refreshFailure = "Mesures non actualisées."
            } else {
                phase = .failed("Lecture de tes mesures impossible.")
            }
        }
    }

    @discardableResult
    private func hydrateFromCache() -> Bool {
        guard let cached = ResponseCache.read(
            [V1BodyMeasurement].self,
            key: ResponseCacheKey.bodyComposition,
            context: modelContext
        ), !cached.isEmpty else { return false }
        measurements = cached
        phase = .loaded
        return true
    }

    private func persistCache() {
        ResponseCache.write(measurements, key: ResponseCacheKey.bodyComposition, context: modelContext)
    }
}

/// One point on the weight line.
nonisolated struct BodyWeightPoint: Identifiable, Equatable, Sendable {
    let day: Date
    let kilograms: Double

    var id: Date { day }
}
