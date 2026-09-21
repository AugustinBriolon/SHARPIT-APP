import Foundation

/// `GET /api/v1/recovery` — mirrors `projectV1Recovery` in the web repository.
///
/// Measures decode as `Double` for the same reason as sleep: nothing guarantees they
/// arrive whole.
nonisolated struct V1RecoveryResponse: Decodable, Sendable, Equatable {
    let apiVersion: Int
    let trainingDayId: String
    let empty: V1DayEmpty?
    let readinessScore: Double?
    let signal: V1RecoverySignal
    let isCalibrating: Bool
    let limiter: String?
    let estimatedRecoveryDays: Double?
    let intensity: String
    let rationale: [String]
    let dimensions: [V1RecoveryDimension]
    let pillars: [V1RecoveryPillar]
    let dissonanceDetected: Bool
    let today: V1RecoveryToday
    let history: [V1RecoveryDay]
    let alerts: [V1RecoveryAlert]
    let keyEvidence: [String]
    let confidencePct: Double?
    let completenessLabel: String
}

/// The signal token the web colors a readout with.
nonisolated enum V1SignalTone: String, Decodable, Sendable {
    case strong, good, moderate, caution, elevated, risk, neutral

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = V1SignalTone(rawValue: raw) ?? .neutral
    }
}

nonisolated struct V1RecoverySignal: Decodable, Sendable, Equatable {
    let label: String
    let tone: V1SignalTone
}

nonisolated struct V1RecoveryDimension: Decodable, Sendable, Equatable, Identifiable {
    let key: String
    let score: Double?
    let status: String

    var id: String { key }
}

nonisolated struct V1RecoveryPillar: Decodable, Sendable, Equatable, Identifiable {
    let key: String
    let label: String
    let tone: V1SignalTone

    var id: String { key }
}

nonisolated struct V1RecoveryToday: Decodable, Sendable, Equatable {
    let hrv: Double?
    let restingHr: Double?
    let bodyBattery: Double?
    let hrvBaselineLow: Double?
    let hrvBaselineHigh: Double?
}

nonisolated struct V1RecoveryDay: Decodable, Sendable, Equatable, Identifiable {
    let date: String
    let hrv: Double?
    let restingHr: Double?

    var id: String { date }
}

nonisolated struct V1RecoveryAlert: Decodable, Sendable, Equatable, Identifiable {
    let key: String
    let label: String
    let tone: V1SignalTone

    var id: String { key }
}
