import Foundation
import Testing
@testable import Sharpit

// MARK: - Draft

private let calendar = Calendar.current

private func day(_ id: String) -> Date { TrainingDayId.date(id)! }

private func coachRun() -> V1PlannedSessionItem {
    V1PlannedSessionItem(
        id: "s1",
        date: day("2026-10-07"),
        startTime: "18:00",
        title: "Seuil",
        type: "RUN",
        durationMin: 50,
        intensity: "THRESHOLD",
        endurancePrescription: .object(["version": .number(1)]),
        isKey: true
    )
}

@Test func anUnchangedDraftWritesNothing() {
    let draft = PlannedSessionDraft(session: coachRun())
    #expect(draft.changes(from: draft).isEmpty)
}

@Test func anEditWritesOnlyWhatChanged() {
    let original = PlannedSessionDraft(session: coachRun())
    var draft = original
    draft.durationMin = 40
    draft.startTime = nil

    let fields = draft.changes(from: original)
    #expect(fields["durationMin"] == .number(40))
    #expect(fields["startTime"] == .null)
    #expect(fields["title"] == nil)
    #expect(fields["type"] == nil)
    #expect(fields["date"] == nil)
}

@Test func aCoachSessionWithoutProseCanStillBeEdited() {
    let original = PlannedSessionDraft(session: coachRun())
    var draft = original
    draft.durationMin = 30
    #expect(draft.missingRequirement(editing: original) == nil)
}

@Test func aSportChangeCarriesTheDetailsAndDropsTheSteps() {
    let original = PlannedSessionDraft(session: coachRun())
    var draft = original
    draft.sport = .bike
    #expect(draft.missingRequirement(editing: original) == "Décris le déroulé de la séance.")

    draft.description = "1 h en zone 2"
    #expect(draft.missingRequirement(editing: original) == nil)
    let fields = draft.changes(from: original)
    #expect(fields["type"] == .string("BIKE"))
    #expect(fields["description"] == .string("1 h en zone 2"))
    #expect(fields["endurancePrescription"] == .null)
}

@Test func aNewSessionNeedsItsDerouleOrItsExercises() {
    var draft = PlannedSessionDraft.new(on: day("2026-10-08"))
    #expect(draft.missingRequirement() == "Décris le déroulé de la séance.")

    draft.sport = .strength
    draft.exercises = [StrengthExerciseDraft()]
    #expect(draft.missingRequirement() == "Ajoute au moins un exercice.")

    draft.exercises[0].name = "Squat"
    #expect(draft.missingRequirement() == nil)
}

@Test func aCreationSendsEveryFieldOnItsLocalDay() throws {
    var draft = PlannedSessionDraft.new(on: day("2026-10-08"))
    draft.description = "40 min faciles"
    draft.title = "  "

    let fields = draft.creation()
    #expect(fields["type"] == .string("RUN"))
    #expect(fields["title"] == .null)
    #expect(fields["intensity"] == .string("ENDURANCE"))
    #expect(fields["durationMin"] == .number(Double(PlannedSessionDraft.defaultDurationMin)))
    let sent = try Date.fromPlannedAPI(try #require(fields["date"]?.string))
    #expect(TrainingDayId.today(now: sent) == "2026-10-08")
}

@Test func aMoveWritesTheDayAlone() {
    let original = PlannedSessionDraft(session: coachRun())
    var draft = original
    draft.day = day("2026-10-09")
    let fields = draft.changes(from: original)
    #expect(fields.values.keys.sorted() == ["date"])
}

@Test func theClockReadsAndWritesTheServersHour() {
    let date = PlannedSessionClock.date(from: "07:05", on: day("2026-10-08"))
    #expect(date.map(PlannedSessionClock.string) == "07:05")
    #expect(PlannedSessionClock.date(from: "25:00", on: day("2026-10-08")) == nil)
}

// MARK: - Strength exercises

@Test func strengthExercisesKeepWhatTheFormDoesNotShow() {
    let stored: JSONValue = .object([
        "version": .number(1),
        "sets": .array([
            .object(["exercise": .string("Fente"), "sets": .number(3), "reps": .number(10), "order": .number(1)]),
            .object([
                "exercise": .string("Squat"), "sets": .number(4), "reps": .number(8), "weightKg": .number(60),
                "order": .number(0), "restSec": .number(90), "garmin": .object(["category": .string("SQUAT")]),
            ]),
        ]),
    ])

    let exercises = StrengthExerciseDraft.exercises(in: stored)
    #expect(exercises.map(\.name) == ["Squat", "Fente"])
    #expect(exercises[0].weightKg == 60)

    let written = StrengthExerciseDraft.prescription(exercises)
    let squat = written["sets"]?.array?.first
    #expect(squat?["restSec"] == .number(90))
    #expect(squat?["garmin"] != nil)
    #expect(squat?["order"] == .number(0))
}

@Test func renamingAnExerciseDropsTheWatchsName() {
    let stored: JSONValue = .object([
        "sets": .array([
            .object([
                "exercise": .string("Squat"), "sets": .number(4), "reps": .number(8),
                "garmin": .object(["category": .string("SQUAT")]), "exerciseCatalogId": .string("cat-1"),
                "restSec": .number(90),
            ]),
        ]),
    ])
    var exercises = StrengthExerciseDraft.exercises(in: stored)
    exercises[0].name = "Squat bulgare"

    let set = StrengthExerciseDraft.prescription(exercises)["sets"]?.array?.first
    #expect(set?["garmin"] == nil)
    #expect(set?["exerciseCatalogId"] == nil)
    #expect(set?["restSec"] == .number(90))
}

@Test func unnamedExercisesAreLeftOut() {
    let written = StrengthExerciseDraft.prescription([StrengthExerciseDraft(), StrengthExerciseDraft(name: "Gainage")])
    #expect(written["sets"]?.array?.count == 1)
    #expect(written["version"] == .number(1))
}

// MARK: - Server refusals

@Test func aRefusalNamesTheFieldsOwnMessage() {
    let body = #"{"error":"Données invalides","details":{"formErrors":[],"fieldErrors":{"description":["Le déroulé de la séance est requis"]}}}"#
    #expect(PlannedSessionClient.refusal(in: Data(body.utf8)) == "Le déroulé de la séance est requis")
    #expect(PlannedSessionClient.refusal(in: Data(#"{"error":"Séance introuvable"}"#.utf8)) == "Séance introuvable")
    #expect(PlannedSessionClient.refusal(in: Data("oops".utf8)) == nil)
}

// MARK: - Moving

@Test func aSessionMovesToTheComingWeekButNotToItsOwnDay() {
    let now = day("2026-10-05")
    let session = V1PlannedSessionItem(id: "s1", date: day("2026-10-07"))
    let days = PlanMoveDays.days(for: session, now: now)
    #expect(days.count == 6)
    #expect(!days.contains { calendar.isDate($0, inSameDayAs: session.date) })
    #expect(PlanMoveDays.label(now, now: now) == "Aujourd’hui")
}

// MARK: - Editor

/// Keeps what it was sent, or refuses as told.
private final class RecordingMutator: PlannedSessionMutating, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [(method: String, id: String?, fields: PlannedSessionFields?)] = []
    let refusal: SharpitAPIError?

    init(refusal: SharpitAPIError? = nil) { self.refusal = refusal }

    var calls: [(method: String, id: String?, fields: PlannedSessionFields?)] {
        lock.withLock { sent }
    }

    func createSession(_ fields: PlannedSessionFields, token _: String) async throws -> V1PlannedSessionItem {
        if let refusal { throw refusal }
        lock.withLock { sent.append(("POST", nil, fields)) }
        return V1PlannedSessionItem(id: "new", date: day("2026-10-08"), type: "RUN")
    }

    func updateSession(id: String, fields: PlannedSessionFields, token _: String) async throws -> V1PlannedSessionItem {
        if let refusal { throw refusal }
        lock.withLock { sent.append(("PATCH", id, fields)) }
        return V1PlannedSessionItem(id: id, date: .now)
    }

    func deleteSession(id: String, token _: String) async throws {
        if let refusal { throw refusal }
        lock.withLock { sent.append(("DELETE", id, nil)) }
    }
}

private struct FixedPlan: PlannedSessionServing {
    let sessions: [V1PlannedSessionItem]
    func plannedSessions(from _: Date, to _: Date, token _: String) async throws -> [V1PlannedSessionItem] { sessions }
}

private struct NoActivities: ActivityServing {
    func activities(token _: String) async throws -> [V1ActivityListItem] { [] }
    func activity(id _: String, token _: String) async throws -> V1ActivityDetail { throw SharpitAPIError.server }
    func activityStream(id _: String, token _: String) async throws -> V1ActivityStreamPayload { throw SharpitAPIError.server }
    func generateNarrative(id _: String, token _: String) async throws -> V1ActivityDetail { throw SharpitAPIError.server }
    func updateSubjective(id _: String, rpe _: Double?, feeling _: String?, token _: String) async throws {}
}

@MainActor
private func loadedPlan(with sessions: [V1PlannedSessionItem]) async -> PlanStore {
    let plan = PlanStore(client: FixedPlan(sessions: sessions), activityClient: NoActivities(), tokenProvider: { "" })
    await plan.load()
    return plan
}

@MainActor
private func sessionIds(in plan: PlanStore) -> [String] {
    guard case .loaded(let entries) = plan.phase else { return [] }
    return entries.compactMap { entry in
        switch entry {
        case .planned(let session), .missed(let session): session.id
        default: nil
        }
    }
}

@MainActor
@Test func aDeletionLeavesThePlanOnTheTapAndGoesOutBehind() async throws {
    let today = calendar.startOfDay(for: .now)
    let plan = await loadedPlan(with: [V1PlannedSessionItem(id: "s1", date: today, type: "RUN")])
    let mutator = RecordingMutator()
    let editor = PlanEditor(mutator: mutator, tokenProvider: { "tok" }, plan: plan)
    var changed = false
    editor.onChanged = { changed = true }

    editor.delete(V1PlannedSessionItem(id: "s1", date: today, type: "RUN"))
    #expect(sessionIds(in: plan).isEmpty)

    for _ in 0..<50 where !changed { try await Task.sleep(for: .milliseconds(10)) }
    #expect(changed)
    #expect(mutator.calls.map(\.method) == ["DELETE"])
}

@MainActor
@Test func anEditShowsAtOnceAndSendsOnlyTheChange() async throws {
    let today = calendar.startOfDay(for: .now)
    let session = V1PlannedSessionItem(id: "s1", date: today, title: "Footing", type: "RUN", durationMin: 45)
    let plan = await loadedPlan(with: [session])
    let mutator = RecordingMutator()
    let editor = PlanEditor(mutator: mutator, tokenProvider: { "tok" }, plan: plan)
    var changed = false
    editor.onChanged = { changed = true }

    let original = PlannedSessionDraft(session: session)
    var draft = original
    draft.durationMin = 30
    let shown = editor.save(draft, from: original, of: session)
    #expect(shown.durationMin == 30)
    #expect(shown.title == "Footing")

    for _ in 0..<50 where !changed { try await Task.sleep(for: .milliseconds(10)) }
    let call = try #require(mutator.calls.first)
    #expect(call.method == "PATCH")
    #expect(call.fields?.values.keys.sorted() == ["durationMin"])
}

@MainActor
@Test func aCreationWaitsForTheServerThenShowsTheSession() async throws {
    let plan = await loadedPlan(with: [])
    let editor = PlanEditor(mutator: RecordingMutator(), tokenProvider: { "tok" }, plan: plan)
    var draft = PlannedSessionDraft.new(on: .now)
    draft.description = "40 min faciles"

    let created = try await editor.create(draft)
    #expect(created.id == "new")
}

@MainActor
@Test func aRefusedCreationSaysTheServersReason() async {
    let plan = await loadedPlan(with: [])
    let editor = PlanEditor(
        mutator: RecordingMutator(refusal: .message("Le déroulé de la séance est requis")),
        tokenProvider: { "tok" },
        plan: plan
    )
    await #expect(throws: SharpitAPIError.self) {
        try await editor.create(PlannedSessionDraft.new(on: .now))
    }
}
