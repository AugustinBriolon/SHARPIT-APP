import Foundation

/// The athlete's verdict on a whole brick (web ADR-059): effort and feeling about the chain,
/// and how the transitions went. Each field is nil until answered.
nonisolated struct V1BrickEvaluation: Codable, Sendable, Equatable {
    var brickGroupId: String
    var rpe: Int?
    var transitionRating: Int?
    var feeling: String?
    var notes: String?
}

nonisolated struct V1BrickEvaluationEnvelope: Decodable, Sendable {
    let evaluation: V1BrickEvaluation?
}
