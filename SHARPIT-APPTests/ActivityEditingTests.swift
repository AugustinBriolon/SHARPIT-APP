import Foundation
import Testing
@testable import Sharpit

// MARK: - Logging a session

@Test func aLoggedRunSendsSecondsAndMetres() {
    var draft = ActivityDraft(date: TrainingDayId.date("2026-10-04")!)
    draft.durationMin = 50
    draft.distanceText = "10,5"
    draft.avgHrText = "148"
    draft.rpe = 6
    draft.feeling = .good

    let fields = draft.creation()
    #expect(fields["type"] == .string("RUN"))
    #expect(fields["duration"] == .number(3000))
    #expect(fields["rpe"] == .number(6))
    #expect(fields["feeling"] == .string("Bien"))
    #expect(fields["runMetrics"]?["distanceM"] == .number(10_500))
    #expect(fields["runMetrics"]?["avgHr"] == .number(148))
    #expect(fields["runMetrics"]?["elevationM"] == nil)
    #expect(fields["strengthSets"] == nil)
}

@Test func aSwimCountsItsDistanceInMetres() {
    var draft = ActivityDraft(date: .now.addingTimeInterval(-600))
    draft.sport = .swim
    draft.distanceText = "1500"
    #expect(draft.creation()["swimMetrics"]?["distanceM"] == .number(1500))
}

@Test func aStrengthSessionNeedsAnExerciseAndSendsItsSets() {
    var draft = ActivityDraft(date: .now.addingTimeInterval(-600))
    draft.sport = .strength
    #expect(draft.missingRequirement == "Ajoute au moins un exercice.")

    draft.exercises = [StrengthExerciseDraft(name: "Squat", sets: 4, reps: 0, weightKg: 60), StrengthExerciseDraft()]
    #expect(draft.missingRequirement == nil)
    let sets = draft.creation()["strengthSets"]?.array
    #expect(sets?.count == 1)
    #expect(sets?.first?["reps"] == .number(1))
    #expect(sets?.first?["weightKg"] == .number(60))
}

@Test func aSessionInTheFutureIsRefused() {
    let draft = ActivityDraft(date: .now.addingTimeInterval(3600))
    #expect(draft.missingRequirement != nil)
}

// MARK: - Editing one

@Test func anEditSendsOnlyWhatMoved() {
    var original = ActivityDraft(date: TrainingDayId.date("2026-10-04")!)
    original.distanceText = "10"
    original.elevationText = "120"
    var draft = original
    draft.elevationText = ""
    draft.notes = "Vent de face"

    let fields = draft.changes(from: original)
    #expect(fields.keys.sorted() == ["notes", "runMetrics"])
    #expect(fields["runMetrics"] == .object(["elevationM": .null]))
}

@Test func aNewSportTakesItsMeasuresWhole() {
    var original = ActivityDraft(date: TrainingDayId.date("2026-10-04")!)
    original.distanceText = "10"
    var draft = original
    draft.sport = .hike
    let fields = draft.changes(from: original)
    #expect(fields["type"] == .string("HIKE"))
    #expect(fields["hikeMetrics"]?["distanceM"] == .number(10_000))
}

@Test func editedSetsGoWithTheType() {
    var original = ActivityDraft(date: TrainingDayId.date("2026-10-04")!)
    original.sport = .strength
    original.exercises = [StrengthExerciseDraft(name: "Squat", sets: 4, reps: 8)]
    var draft = original
    draft.exercises[0].reps = 10
    let fields = draft.changes(from: original)
    #expect(fields["type"] == .string("STRENGTH"))
    #expect(fields["strengthSets"]?.array?.first?["reps"] == .number(10))
}

// MARK: - Pain after a session

private func zone(_ id: String, category: String = "PAIN", status: String = "ACTIVE", severity: Int, readings: [String] = []) throws -> V1SensitiveZone {
    let timeline = readings.enumerated().map { index, date in
        #"{"id":"r\#(index)","date":"\#(date)","kind":"reading","label":"Point","severity":3}"#
    }.joined(separator: ",")
    let json = """
    {"id":"\(id)","title":"Genou \(id)","category":"\(category)","categoryLabel":"Douleur","bodyPart":"Genou",
     "side":"LEFT","sideLabel":"Gauche","status":"\(status)","statusLabel":"Active","severity":\(severity),
     "startDate":"2026-09-01T08:00:00.000Z","resolvedAt":null,"strategy":"protect","strategyLabel":"À protéger",
     "strategyDetail":"","timeline":[\(timeline)]}
    """
    return try JSONDecoder().decode(V1SensitiveZone.self, from: Data(json.utf8))
}

@Test func aRecentSessionAsksAboutOpenPainsWorstFirst() throws {
    let session = Date.fromAPIOrNil("2026-10-04T07:00:00.000Z")
    let now = Date.fromAPIOrNil("2026-10-04T12:00:00.000Z")
    let zones = try [
        zone("a", severity: 2),
        zone("b", severity: 7),
        zone("c", severity: 5, readings: ["2026-10-04T09:00:00.000Z"]),
        zone("d", status: "RESOLVED", severity: 4),
        zone("e", category: "MOBILITY", severity: 6),
    ]
    let due = PainReassessment.due(after: session, zones: zones, now: now)
    #expect(due.map(\.id) == ["b", "a"])
    #expect(due.first?.question == "Comment va « Genou b » après cette séance ?")
}

@Test func anOldSessionAsksNothing() throws {
    let session = Date.fromAPIOrNil("2026-09-20T07:00:00.000Z")
    let now = Date.fromAPIOrNil("2026-10-04T12:00:00.000Z")
    #expect(PainReassessment.due(after: session, zones: [try zone("a", severity: 5)], now: now).isEmpty)
}

private extension Date {
    static func fromAPIOrNil(_ text: String) -> Date {
        (try? Date.fromAPI(text)) ?? .distantPast
    }
}
