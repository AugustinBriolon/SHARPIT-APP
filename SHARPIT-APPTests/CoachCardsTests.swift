import Foundation
import Testing
@testable import Sharpit

/// The web's contract fixtures (SHARPIT `coach/chat/cards/fixtures`), decoded the app's way.
private func cardPart(_ name: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: fixtureData("CoachCards/\(name)"))
}

private func replacing(_ key: String, with value: JSONValue, in part: JSONValue) -> JSONValue {
    guard case .object(var fields) = part else { return part }
    fields[key] = value
    return .object(fields)
}

@Test func anIntervalWorkoutDecodesWithItsRepeatedGroup() throws {
    let workout = try #require(CoachWorkout(part: try cardPart("workout-run-intervals.json")))

    #expect(workout.type == .run)
    #expect(workout.intensity == "THRESHOLD")
    #expect(workout.durationMin == 60)
    let blocks = try #require(workout.endurancePrescription?.blocks)
    #expect(blocks.map(\.repeats) == [1, 6, 1])
    #expect(blocks[1].steps.map(\.kind) == ["interval", "recovery"])
    #expect(CoachWorkoutFormat.stepDetail(blocks[1].steps[0]) == "1 km · Seuil")
    #expect(CoachWorkoutFormat.stepKind(blocks[1].steps[0]) == "Travail")
    #expect(workout.warnings.count == 1)
}

@Test func aStrengthWorkoutReadsItsExercisesAndNulls() throws {
    let workout = try #require(CoachWorkout(part: try cardPart("workout-strength.json")))
    let exercises = try #require(workout.strengthPrescription?.sets)

    #expect(workout.endurancePrescription == nil)
    #expect(CoachWorkoutFormat.exercise(exercises[0]) == "3 × 10 · 20 kg · repos 90 s")
    // Explicit nulls (weightKg, restSec, notes) read as absent.
    #expect(CoachWorkoutFormat.exercise(exercises[1]) == "3 × 45 s · repos au Lap")
    #expect(exercises[1].notes == nil)
    #expect(workout.warnings.isEmpty)
}

@Test func aMinimalWorkoutDrawsWithoutFigures() throws {
    let workout = try #require(CoachWorkout(part: try cardPart("workout-minimal.json")))

    #expect(workout.type == .swim)
    #expect(workout.endurancePrescription == nil && workout.strengthPrescription == nil)
    #expect(CoachWorkoutFormat.summary(workout, isExpertReading: false) == nil)
}

@MainActor
@Test func theSummaryNamesLoadInTheReadingsWords() throws {
    let workout = try #require(CoachWorkout(part: try cardPart("workout-run-intervals.json")))

    #expect(CoachWorkoutFormat.summary(workout, isExpertReading: false) == "60 min · charge 72")
    #expect(CoachWorkoutFormat.summary(workout, isExpertReading: true) == "60 min · 72 TSS")
}

@Test func anInvalidOrUnfinishedCardIsLeftOut() throws {
    #expect(CoachWorkout(part: try cardPart("workout-invalid.json")) == nil)

    let valid = try cardPart("workout-run-intervals.json")
    #expect(CoachWorkout(part: replacing("state", with: .string("input-streaming"), in: valid)) == nil)
    #expect(CoachWorkout(part: replacing("output", with: .object(["ok": .bool(false), "error": .string("x")]), in: valid)) == nil)
    #expect(CoachWorkout(part: replacing("output", with: .object(["ok": .bool(true), "schemaVersion": .number(2)]), in: valid)) == nil)
    // Another tool's part never reads as a card.
    #expect(CoachWorkout(part: replacing("type", with: .string("tool-createPlannedSession"), in: valid)) == nil)
}

@Test func followUpsDecodeInOrder() throws {
    let followUps = try #require(CoachFollowUps(part: try cardPart("follow-ups.json")))

    #expect(followUps.suggestions.count == 3)
    #expect(followUps.suggestions.first == "Et si je n’ai que 45 min ?")
}

@Test func aTurnReadsProseThenItsCards() throws {
    let message = CoachMessage(role: .assistant, text: "", parts: [
        .object(["type": .string("step-start")]),
        .object(["type": .string("text"), "text": .string("Voici ta séance.")]),
        try cardPart("workout-run-intervals.json"),
        try cardPart("workout-invalid.json"),
        try cardPart("follow-ups.json"),
    ])

    let ids = CoachSegment.segments(of: message).map(\.id)
    #expect(ids == ["text-0", "workout-call-run-1", "follow-ups-call-follow-1"])
    // The cards are not prose: copying the answer takes its words only.
    #expect(CoachMessageCopy.plainText(of: message) == "Voici ta séance.")
}

// The data cards (SHARPIT ADR-119): the web's fixtures, decoded the app's way.
private func dataCardPart(_ name: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: fixtureData("CoachDataCards/\(name)"))
}

@Test func theDayScoresCardKeepsTheToolsOwnFigures() throws {
    let card = try #require(CoachDataCard(part: try dataCardPart("day-scores.json")))

    guard case .dayScores(let scores) = card else { Issue.record("not a day scores card"); return }
    #expect(scores.energyBank == .init(value: 71, typicalBaseline: 64))
    #expect(scores.stress == 38 && scores.readiness == 66)
    #expect(CoachDataCardFormat.band(try #require(scores.targetBand)) == "8–12")
}

@Test func theSleepCardReadsAMissingNightAsAbsentNotZero() throws {
    let card = try #require(CoachDataCard(part: try dataCardPart("sleep-vs-readiness.json")))

    guard case .sleepVsReadiness(let days, let points) = card else { Issue.record("not a sleep card"); return }
    #expect(days == 7)
    #expect(points[1].sleepMinutes == nil && points[1].readiness == 55)
    #expect(CoachDataCardFormat.sleep(try #require(points[0].sleepMinutes)) == "6 h 50")
}

@Test func theTargetBandCardWordsItsStatus() throws {
    let card = try #require(CoachDataCard(part: try dataCardPart("target-band.json")))

    guard case .targetBand(_, let band, let readiness) = card else { Issue.record("not a band card"); return }
    #expect(CoachDataCardFormat.status(band.status) == "sous la cible")
    #expect(readiness == nil)
}

@Test func aDataCardOfAnotherVersionOrStillRunningIsLeftOut() throws {
    let part = try dataCardPart("day-scores.json")
    guard case .object(var fields) = part, case .object(var output)? = fields["output"] else { return }
    output["schemaVersion"] = .number(2)
    fields["output"] = .object(output)
    #expect(CoachDataCard(part: .object(fields)) == nil)

    fields["state"] = .string("input-available")
    output["schemaVersion"] = .number(1)
    fields["output"] = .object(output)
    #expect(CoachDataCard(part: .object(fields)) == nil)
}

@Test func aReadToolPartWithoutACardDrawsNothing() throws {
    let part = try JSONDecoder().decode(JSONValue.self, from: Data("""
    {"type":"tool-explainDayScores","state":"output-available","input":{},"output":{"ok":true,"markdown":"x"}}
    """.utf8))
    #expect(CoachDataCard(part: part) == nil)
}
