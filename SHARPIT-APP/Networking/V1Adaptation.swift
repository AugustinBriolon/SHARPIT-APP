import Foundation

/// `GET /api/v1/adaptation` — mirrors `projectV1Adaptation` in the web repository: how the
/// body answers the load, what holds it back, and what the next block's load becomes.
nonisolated struct V1AdaptationResponse: Decodable, Sendable, Equatable {
    let apiVersion: Int
    let trainingDayId: String
    let empty: V1DayEmpty?
    /// 0–100.
    let index: Double?
    let status: V1AdaptationStatus
    /// « En progression », « Stable »… — « — » when no trend is read.
    let trendLabel: String
    let verdict: V1AdaptationVerdict
    /// Applied to the next block: under 1 the model eases the volume, above it opens more.
    let loadMultiplier: Double
    let rationale: [String]
    let keyEvidence: [String]
    /// The label of the dimension holding the adaptation back.
    let limitingFactor: String?
    let plateauRisk: Bool
    let overreachingWithoutAdaptation: Bool
    /// Higher is better.
    let dimensions: [V1AdaptationDimension]
    /// Days of history the reading stands on.
    let historyLength: Double
    let confidencePct: Double?
}

nonisolated struct V1AdaptationStatus: Decodable, Sendable, Equatable {
    let label: String
    let tone: V1SignalTone
}

nonisolated struct V1AdaptationVerdict: Decodable, Sendable, Equatable {
    let key: String
    let label: String
    let tone: V1SignalTone
}

nonisolated struct V1AdaptationDimension: Decodable, Sendable, Equatable, Identifiable {
    let key: String
    let label: String
    let description: String
    let available: Bool
    let score: Double?
    let isLimiting: Bool

    var id: String { key }
}

nonisolated protocol AdaptationServing: Sendable {
    func adaptation(trainingDayId: String, token: String) async throws -> V1AdaptationResponse
}
