import Foundation

/// `GET /api/v1/effort` — mirrors `projectV1Effort` in the web repository: the day's strain,
/// what it implies, the five fatigue dimensions and the load behind them.
///
/// Every measure decodes as `Double`, as recovery's do: nothing guarantees they arrive whole.
nonisolated struct V1EffortResponse: Decodable, Sendable, Equatable {
    let apiVersion: Int
    let trainingDayId: String
    let empty: V1DayEmpty?
    let strain: V1EffortStrain
    let verdict: V1EffortVerdict
    let fatigueTypeLabel: String?
    /// `FULL`, `REDUCED`, `LIGHT_ONLY` or `REST_ONLY`.
    let trainingCapacity: String
    let rationale: [String]
    let keyEvidence: [String]
    let consecutiveDays: Double
    let estimatedDaysToFresh: Double?
    let load: V1EffortLoad
    /// Every fatigue dimension in the web's order, missing ones included. Higher is worse.
    let dimensions: [V1EffortDimension]
    /// The key of the dimension that weighs most, when one does.
    let dominantDimension: String?
    let limitingFactor: String?
    let overreaching: V1EffortOverreaching?
    let composition: V1EffortComposition
    /// Oldest first, one point per day of the window ending on `trainingDayId`.
    let pmc: [V1EffortPmcPoint]
    /// Oldest first, eight weeks ending with this one.
    let weeklyTss: [V1EffortWeek]
    let confidencePct: Double?
    let completenessLabel: String
}

/// The day's strain, 0–21, worded and toned as the web's ring.
nonisolated struct V1EffortStrain: Decodable, Sendable, Equatable {
    let score: Double?
    let label: String
    let subtitle: String
    let tone: V1SignalTone
}

nonisolated struct V1EffortVerdict: Decodable, Sendable, Equatable {
    let key: String
    let label: String
    let tone: V1SignalTone
}

nonisolated struct V1EffortLoad: Decodable, Sendable, Equatable {
    let daily: Double
    let weekly: Double
    let acwr: Double
    let chronicWeeklyAvg: Double?
    let tsb: Double?
    let avgWeeklyTss: Double
}

nonisolated struct V1EffortDimension: Decodable, Sendable, Equatable, Identifiable {
    let key: String
    let label: String
    let description: String
    let available: Bool
    let score: Double?
    /// « Faible », « Modérée », « Élevée », « Critique » — the web's words for the score.
    let intensity: String?

    var id: String { key }
}

nonisolated struct V1EffortOverreaching: Decodable, Sendable, Equatable {
    let label: String
    let tone: V1SignalTone
}

/// What made up the day's strain: training, the cardiovascular day, movement.
nonisolated struct V1EffortComposition: Decodable, Sendable, Equatable {
    let available: Bool
    let dominantKey: String?
    let contributors: [V1EffortContributor]
    let signals: V1EffortDailySignals
}

nonisolated struct V1EffortContributor: Decodable, Sendable, Equatable, Identifiable {
    let key: String
    let label: String
    let description: String
    let available: Bool
    let load: Double?
    let score: Double?
    let signalSummary: String?

    var id: String { key }
}

nonisolated struct V1EffortDailySignals: Decodable, Sendable, Equatable {
    let steps: Double?
    let stress: Double?
    let bodyBattery: Double?
}

nonisolated struct V1EffortPmcPoint: Decodable, Sendable, Equatable, Identifiable {
    let date: String
    let ctl: Double
    let atl: Double
    let tsb: Double

    var id: String { date }
}

nonisolated struct V1EffortWeek: Decodable, Sendable, Equatable {
    let label: String
    let tss: Double
}

nonisolated protocol EffortServing: Sendable {
    func effort(trainingDayId: String, token: String) async throws -> V1EffortResponse
}
