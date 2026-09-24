import Foundation
import Observation

/// What Corps reads: the weigh-ins, the recovery nights, the profile's thresholds and their
/// history — four reads made together, each allowed to fail on its own.
///
/// A missing scale costs the Composition section, not the screen: only when nothing at all
/// answers is Corps a failure. The values come from the web's `/api/v1/body/overview`; the
/// resources the app already reads are fetched alongside for the tiles' small trends, and
/// stand in for the overview on a server that does not serve it yet.
@MainActor
@Observable
final class CorpsStore {
    enum Phase: Equatable {
        case loading
        case loaded
        /// Everything answered and nothing was measured yet.
        case empty
        case failed(String)
        case unauthorized
    }

    /// A year of weigh-ins: the drawer's longest range.
    static let bodyWindowDays = 365

    private(set) var phase: Phase = .loading
    private(set) var metrics: [CorpsMetric] = []
    /// The athlete's weight target, drawn on the weight's hero and chart.
    private(set) var targetWeightKg: Double?

    private let overviewClient: any BodyServing
    private let profileClient: any AthleteProfileServing
    private let bodyClient: any BodyCompositionServing
    private let recoveryClient: any RecoveryServing
    private let tokenProvider: () async throws -> String

    init(
        overviewClient: any BodyServing = BodyClient(),
        profileClient: any AthleteProfileServing,
        bodyClient: any BodyCompositionServing,
        recoveryClient: any RecoveryServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.overviewClient = overviewClient
        self.profileClient = profileClient
        self.bodyClient = bodyClient
        self.recoveryClient = recoveryClient
        self.tokenProvider = tokenProvider
    }

    func metrics(in section: CorpsSection) -> [CorpsMetric] {
        metrics.filter { $0.key.section == section }
    }

    func metric(_ key: CorpsMetricKey) -> CorpsMetric? {
        metrics.first { $0.key == key }
    }

    func load() async {
        let token: String
        do {
            token = try await tokenProvider()
        } catch {
            phase = .unauthorized
            return
        }

        // Captured before the concurrent reads: the clients are Sendable, the store is not
        // theirs to reach into from another executor.
        let overviewClient = overviewClient
        let profileClient = profileClient
        let bodyClient = bodyClient
        let recoveryClient = recoveryClient
        let today = TrainingDayId.today()
        let window = Self.bodyWindowDays

        async let profile = corpsAttempt { try await profileClient.athleteProfile(token: token) }
        async let measurements = corpsAttempt {
            try await bodyClient.bodyComposition(days: window, token: token)
        }
        async let recovery = corpsAttempt {
            try await recoveryClient.recovery(trainingDayId: today, token: token)
        }
        async let thresholds = corpsAttempt { try await profileClient.thresholdHistory(token: token) }
        async let overview = corpsAttempt { try await overviewClient.bodyOverview(token: token) }

        let results = await (profile, measurements, recovery, thresholds)
        let web = await overview
        let outcomes: [CorpsReadOutcome] = [
            results.0.outcome, results.1.outcome, results.2.outcome, results.3.outcome, web.outcome,
        ]

        if outcomes.contains(.unauthorized) {
            phase = .unauthorized
            return
        }
        if outcomes.allSatisfy({ $0 == .failed }) {
            if metrics.isEmpty { phase = .failed("Lecture de ton corps impossible.") }
            return
        }

        let local = CorpsReadout.metrics(
            profile: results.0.value,
            measurements: results.1.value ?? [],
            recovery: results.2.value,
            thresholds: results.3.value ?? []
        )
        let assembled = web.value.map { CorpsReadout.merging(overview: $0, localSeries: local) } ?? local
        targetWeightKg = results.0.value?.targetWeightKg
        SharpitMotion.run {
            metrics = assembled
            phase = assembled.isEmpty ? .empty : .loaded
        }
    }

    /// One metric over a range, from the web; the series already on the tile when the web
    /// cannot answer, cut to the range.
    func series(for metric: CorpsMetric, range: CorpsRange) async -> [CorpsPoint] {
        let overviewClient = overviewClient
        let key = metric.key
        if let token = try? await tokenProvider(),
           let series = try? await overviewClient.bodySeries(metric: key, range: range, token: token) {
            return CorpsReadout.points(from: series)
        }
        return range.filter(metric.series)
    }
}

nonisolated enum CorpsReadOutcome: Equatable, Sendable {
    case ok
    case failed
    case unauthorized
}

nonisolated struct CorpsRead<Value: Sendable>: Sendable {
    let value: Value?
    let outcome: CorpsReadOutcome
}

/// One of Corps' reads, turned into a value or the reason there is none.
nonisolated func corpsAttempt<Value: Sendable>(
    _ work: @Sendable () async throws -> Value
) async -> CorpsRead<Value> {
    do {
        return CorpsRead(value: try await work(), outcome: .ok)
    } catch SharpitAPIError.unauthorized {
        return CorpsRead(value: nil, outcome: .unauthorized)
    } catch {
        return CorpsRead(value: nil, outcome: .failed)
    }
}
