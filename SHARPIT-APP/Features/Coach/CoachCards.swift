import Foundation

/// The coach's native cards (SHARPIT ADR-111): the inputs of its display tools, decoded into
/// typed models. The server's zod schemas are the contract (`coach-cards.ts`); the fixtures in
/// `SHARPIT-APPTests/Fixtures/CoachCards` are a copy of the web's, kept identical by its tests.
nonisolated enum CoachCards {
    /// The contract this build draws. A card stamped with another version is left out — its
    /// prose still reads.
    static let schemaVersion = 1

    static let workoutToolType = "tool-presentWorkout"
    static let followUpsToolType = "tool-suggestFollowUps"

    /// The part's input once the card is whole and the server did not refuse it; nil otherwise.
    static func decodedInput<Card: Decodable>(_ type: Card.Type, of part: JSONValue, toolType: String) -> Card? {
        guard part["type"]?.string == toolType,
              let state = part["state"]?.string,
              state == "input-available" || state == "output-available",
              part["output"]?["ok"] != .bool(false),
              part["output"]?["schemaVersion"]?.number.map({ Int($0) == schemaVersion }) ?? true,
              let input = part["input"],
              let data = try? JSONEncoder().encode(input)
        else { return nil }
        return try? JSONDecoder().decode(Card.self, from: data)
    }
}

/// A session the coach proposes to read, not yet in the plan.
nonisolated struct CoachWorkout: Decodable, Equatable, Sendable {
    let type: V1ActivityType
    let title: String
    let purpose: String
    let intensity: String?
    let durationMin: Double?
    let load: Double?
    let endurancePrescription: Endurance?
    let strengthPrescription: Strength?
    let warnings: [String]

    struct Endurance: Decodable, Equatable, Sendable {
        let blocks: [Block]
        let poolLengthM: Double?
    }

    /// One step, or a group of steps repeated `times`.
    struct Block: Decodable, Equatable, Sendable {
        let times: Int?
        let steps: [Step]

        var repeats: Int { max(times ?? 1, 1) }
    }

    struct Step: Decodable, Equatable, Sendable {
        let kind: String
        let minutes: Double?
        let meters: Double?
        let lap: Bool?
        let effort: String?
        let stroke: String?
        let notes: String?
    }

    struct Strength: Decodable, Equatable, Sendable {
        let sets: [Exercise]
    }

    struct Exercise: Decodable, Equatable, Sendable {
        let exercise: String
        let sets: Int
        let reps: Int
        let durationSec: Int?
        let weightKg: Double?
        let restMode: String?
        let restSec: Int?
        let notes: String?
    }

    init?(part: JSONValue) {
        guard let decoded = CoachCards.decodedInput(Self.self, of: part, toolType: CoachCards.workoutToolType) else { return nil }
        self = decoded
    }
}

/// The questions the coach offers to go on with, sent as the athlete's own on a tap.
nonisolated struct CoachFollowUps: Decodable, Equatable, Sendable {
    let suggestions: [String]

    init?(part: JSONValue) {
        guard let decoded = CoachCards.decodedInput(Self.self, of: part, toolType: CoachCards.followUpsToolType),
              !decoded.suggestions.isEmpty
        else { return nil }
        self = decoded
    }
}

/// How a workout card words its figures — the coach's words, the plan's units.
enum CoachWorkoutFormat {
    static func stepKind(_ step: CoachWorkout.Step) -> String {
        CoachProposal.stepKinds[step.kind] ?? step.kind
    }

    /// « 1 km · Seuil », « 2 min · Récupération · Crawl ».
    static func stepDetail(_ step: CoachWorkout.Step) -> String {
        let amount = step.lap == true && step.minutes == nil && step.meters == nil
            ? String(localized: "jusqu'au Lap")
            : (step.minutes.map(duration) ?? step.meters.map(distance))
        let effort = step.effort.map { CoachProposal.intensityLabels[$0] ?? $0 }
        let stroke = step.stroke.flatMap { strokes[$0] }
        return [amount, effort, stroke].compactMap { $0 }.joined(separator: " · ")
    }

    /// « 3 × 10 · 20 kg · repos 90 s », « 3 × 45 s · repos au Lap ».
    static func exercise(_ exercise: CoachWorkout.Exercise) -> String {
        let work = exercise.reps == 0
            ? exercise.durationSec.map { "\(exercise.sets) × \($0) s" } ?? "\(exercise.sets) séries"
            : "\(exercise.sets) × \(exercise.reps)"
        let weight = exercise.weightKg.flatMap { $0 > 0 ? "\(number($0)) kg" : nil }
        let rest: String? = exercise.restMode == "time"
            ? exercise.restSec.map { String(localized: "repos \($0) s") }
            : String(localized: "repos au Lap")
        return [work, weight, rest].compactMap { $0 }.joined(separator: " · ")
    }

    /// « 60 min · charge 72 », or nil when the coach gave neither.
    static func summary(_ workout: CoachWorkout, isExpertReading: Bool) -> String? {
        let parts = [
            workout.durationMin.map(duration),
            workout.load.map { ActivityFormat.trainingLoad($0, isExpertReading: isExpertReading) },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func duration(_ minutes: Double) -> String {
        guard minutes.isFinite, minutes >= 1 else { return "\(Int(exactly: (minutes * 60).rounded()) ?? 0) s" }
        return "\(Int(exactly: minutes.rounded()) ?? 0) min"
    }

    static func distance(_ meters: Double) -> String {
        guard meters.isFinite else { return "—" }
        return meters >= 1000 ? "\(number(meters / 1000)) km" : "\(Int(exactly: meters.rounded()) ?? 0) m"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.locale))
    }

    private static let strokes = [
        "free": String(localized: "Crawl"), "back": String(localized: "Dos"), "breast": String(localized: "Brasse"),
        "fly": String(localized: "Papillon"), "im": String(localized: "4 nages"), "drill": String(localized: "Éducatif"),
        "mixed": String(localized: "Nage au choix"),
    ]
}
