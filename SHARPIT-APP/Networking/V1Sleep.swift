import Foundation

/// `GET /api/v1/sleep` — mirrors `projectV1Sleep` in the web repository.
///
/// Every measure decodes as `Double`: the server computes some of them (averages,
/// regularity) and nothing guarantees they arrive whole, and one fractional value would
/// fail the whole payload.
nonisolated struct V1SleepResponse: Decodable, Sendable, Equatable {
    let apiVersion: Int
    let trainingDayId: String
    let nightStatus: V1SleepNightStatus
    let empty: V1DayEmpty?
    let score: Double?
    let adequacy: V1SleepAdequacy
    let durationMin: Double?
    let targetMin: Double
    let targetDeltaMin: Double?
    let delta7dMin: Double?
    let stages: V1SleepStages
    /// Minutes after midnight.
    let bedtimeMin: Double?
    let wakeMin: Double?
    let breakdown: V1SleepBreakdown
    let averages: V1SleepAverages
    let regularityMin: Double?
    let recommendedBedtimeMin: Double?
    let recommendedDurationMin: Double?
    let debt7Min: Double?
    let debt14Min: Double?
    let recoveryNote: String?
    let history: [V1SleepNight]
    let insights: [V1SleepInsight]
    let confidencePct: Double?
}

nonisolated enum V1SleepNightStatus: String, Decodable, Sendable {
    case present
    case pending
    case missing
}

/// The empty state of a v1 day resource.
nonisolated struct V1DayEmpty: Decodable, Sendable, Equatable {
    let title: String
    let message: String?
}

nonisolated struct V1SleepAdequacy: Decodable, Sendable, Equatable {
    let key: Key
    let label: String

    nonisolated enum Key: String, Decodable, Sendable {
        case excellent = "EXCELLENT"
        case adequate = "ADEQUATE"
        case insufficient = "INSUFFICIENT"
        case severelyInsufficient = "SEVERELY_INSUFFICIENT"
        case pending = "PENDING"
        case missing = "MISSING"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Key(rawValue: raw) ?? .unknown
        }
    }
}

nonisolated struct V1SleepStages: Decodable, Sendable, Equatable {
    let deepMin: Double?
    let remMin: Double?
    let lightMin: Double?
    let awakeMin: Double?
}

nonisolated struct V1SleepBreakdown: Decodable, Sendable, Equatable {
    let durationScore: Double?
    let architectureScore: Double?
    let restorativeRatio: Double?
}

nonisolated struct V1SleepAverages: Decodable, Sendable, Equatable {
    let score: Double?
    let durationMin: Double?
    let deepPct: Double?
    let remPct: Double?
    let nights: Int
}

nonisolated struct V1SleepNight: Decodable, Sendable, Equatable, Identifiable {
    let date: String
    let minutes: Double?

    var id: String { date }
}

/// The web's `RecoveryTone` — shared by sleep and recovery insights.
nonisolated enum V1RecoveryTone: String, Decodable, Sendable {
    case good
    case moderate
    case low
    case neutral

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = V1RecoveryTone(rawValue: raw) ?? .neutral
    }
}

nonisolated struct V1SleepInsight: Decodable, Sendable, Equatable, Hashable {
    let tone: V1RecoveryTone
    let title: String
    let detail: String
}
