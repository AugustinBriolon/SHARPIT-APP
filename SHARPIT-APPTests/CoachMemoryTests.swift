import Foundation
import Testing
@testable import Sharpit

private final class StubCoachMemoryClient: CoachMemoryServing, @unchecked Sendable {
    var stubbedSnapshot: CoachMemorySnapshot

    init(stubbedSnapshot: CoachMemorySnapshot = CoachMemorySnapshot()) {
        self.stubbedSnapshot = stubbedSnapshot
    }

    func snapshot(token: String) async throws -> CoachMemorySnapshot {
        stubbedSnapshot
    }

    var contextFailure: (any Error)?
    /// Runs while the context save is in flight, to read what the athlete sees before the answer.
    var duringContextSave: (@Sendable () async -> Void)?

    func saveProfileContext(_ context: String, token: String) async throws {
        await duringContextSave?()
        if let contextFailure { throw contextFailure }
    }

    func createEntry(_ input: CreateCoachMemoryInput, token: String) async throws -> CoachMemoryEntry {
        let entry = CoachMemoryEntry(
            id: UUID().uuidString,
            type: input.type,
            label: input.label,
            locationLabel: input.locationLabel,
            startDate: input.startDate,
            endDate: input.endDate,
            note: input.note,
            trainingConstraint: input.trainingConstraint ?? .full,
            allowedDisciplines: input.allowedDisciplines
        )
        stubbedSnapshot.entries.insert(entry, at: 0)
        return entry
    }

    var updateFailure: (any Error)?

    func updateEntry(id: String, _ input: CreateCoachMemoryInput, token: String) async throws -> CoachMemoryEntry {
        if let updateFailure { throw updateFailure }
        let entry = CoachMemoryEntry(
            id: id,
            type: input.type,
            label: input.label,
            locationLabel: input.locationLabel,
            startDate: input.startDate,
            endDate: input.endDate,
            note: input.note,
            trainingConstraint: input.trainingConstraint ?? .full,
            allowedDisciplines: input.allowedDisciplines
        )
        stubbedSnapshot.entries.removeAll { $0.id == id }
        stubbedSnapshot.entries.append(entry)
        return entry
    }

    func deleteEntry(id: String, token: String) async throws {
        stubbedSnapshot.entries.removeAll { $0.id == id }
    }
}

@Test func coachMemoryEntryDecodesFromJson() throws {
    let json = """
    {
        "id": "entry_1",
        "type": "TRAVEL",
        "label": "Voyage Pro",
        "locationLabel": "Londres, UK",
        "startDate": "2026-10-01T00:00:00.000Z",
        "endDate": "2026-10-05T00:00:00.000Z",
        "note": "Hôtel avec petite salle",
        "trainingConstraint": "REDUCED",
        "isActive": true
    }
    """
    let entry = try JSONDecoder().decode(CoachMemoryEntry.self, from: Data(json.utf8))
    #expect(entry.id == "entry_1")
    #expect(entry.type == .travel)
    #expect(entry.label == "Voyage Pro")
    #expect(entry.locationLabel == "Londres, UK")
    #expect(entry.trainingConstraint == .reduced)
    #expect(entry.isActive)
    #expect(entry.displayTitle == "Voyage Pro")
    #expect(entry.allowedDisciplines == nil)
}

@Test func coachMemoryEntryDecodesAllowedDisciplinesFromJson() throws {
    let json = """
    {
        "id": "entry_2",
        "type": "TRAVEL",
        "label": "Déplacement Paris",
        "locationLabel": "Paris, France",
        "startDate": "2026-11-01T00:00:00.000Z",
        "endDate": "2026-11-03T00:00:00.000Z",
        "trainingConstraint": "REDUCED",
        "allowedDisciplines": ["RUN", "MOBILITY"],
        "isActive": false
    }
    """
    let entry = try JSONDecoder().decode(CoachMemoryEntry.self, from: Data(json.utf8))
    #expect(entry.allowedDisciplines == ["RUN", "MOBILITY"])
}

@Test func coachMemoryInputEncodesAllowedDisciplines() throws {
    let now = Date()
    let end = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
    let input = CreateCoachMemoryInput(
        type: .travel,
        label: "Séminaire",
        locationLabel: "Lyon, France",
        startDate: now,
        endDate: end,
        note: nil,
        trainingConstraint: .reduced,
        allowedDisciplines: ["RUN", "BIKE", "STRENGTH"]
    )
    let data = try JSONEncoder().encode(input)
    let dict = try JSONDecoder().decode([String: JSONValue].self, from: data)

    guard case .array(let disciplines) = dict["allowedDisciplines"] else {
        Issue.record("Expected allowedDisciplines array in encoded input")
        return
    }
    #expect(disciplines.contains(.string("RUN")))
    #expect(disciplines.contains(.string("BIKE")))
    #expect(disciplines.contains(.string("STRENGTH")))
}

@MainActor
@Test func coachMemoryStoreDetectsDirtyContext() async {
    let snap = CoachMemorySnapshot(
        entries: [],
        activeId: nil,
        profileContext: "Je m'entraîne le matin."
    )
    let client = StubCoachMemoryClient(stubbedSnapshot: snap)
    let store = CoachMemoryStore(client: client, tokenProvider: { "token" })

    await store.load()
    #expect(!store.isContextDirty)

    store.profileContextText = "Je m'entraîne le soir."
    #expect(store.isContextDirty)

    store.profileContextText = "Je m'entraîne le matin."
    #expect(!store.isContextDirty)
}

@MainActor
@Test func coachMemoryStoreCreatesAndDeletesEntryWithImmediateReactivity() async {
    let client = StubCoachMemoryClient()
    let store = CoachMemoryStore(client: client, tokenProvider: { "token" })

    await store.load()
    #expect(store.entries.isEmpty)

    let input = CreateCoachMemoryInput(
        type: .travel,
        label: "Stage d'entraînement",
        locationLabel: "Font-Romeu",
        startDate: Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
        note: "Altitude",
        trainingConstraint: .full,
        allowedDisciplines: ["RUN", "BIKE"]
    )

    let created = await store.createEntry(input)
    #expect(created)
    #expect(store.entries.count == 1)
    #expect(store.entries.first?.label == "Stage d'entraînement")
    #expect(store.entries.first?.locationLabel == "Font-Romeu")

    if let id = store.entries.first?.id {
        await store.deleteEntry(id: id)
        #expect(store.entries.isEmpty)
    }
}


@MainActor
@Test func coachContextCountsAsSavedOnTheTap() async {
    let client = StubCoachMemoryClient()
    let failures = SharpitWriteFailures()
    let store = CoachMemoryStore(client: client, tokenProvider: { "token" }, failures: failures)
    store.profileContextText = "Je m'entraîne le soir."
    let dirtyDuringSave = DirtyFlag()
    client.duringContextSave = { await MainActor.run { dirtyDuringSave.value = store.isContextDirty } }

    await store.saveContext()
    #expect(dirtyDuringSave.value == false)
    #expect(!store.isContextDirty)
    #expect(failures.latest == nil)
}

@MainActor
@Test func coachContextThatFailsForGoodIsDirtyAgainAndSaid() async {
    let client = StubCoachMemoryClient()
    client.contextFailure = SharpitAPIError.badRequest
    let failures = SharpitWriteFailures()
    let store = CoachMemoryStore(client: client, tokenProvider: { "token" }, failures: failures)
    store.profileContextText = "Je m'entraîne le soir."

    await store.saveContext()
    #expect(store.isContextDirty)
    #expect(failures.latest?.message == "Contexte non enregistré. Réessaie dans un instant.")
}

@MainActor
private final class DirtyFlag {
    var value: Bool?
}

// MARK: - The form against the server's rules (`resolveTrainingFields`)

@Test func tripTrainingSendsOnlyWhatTheServerHonours() {
    var training = TripTraining()
    #expect(training.constraint == .full)
    #expect(training.allowedDisciplines == nil)

    training.mode = .lighter
    #expect(training.constraint == .reduced)
    #expect(training.allowedDisciplines == nil)

    training.mode = .pause
    #expect(training.constraint == .none)
    #expect(training.allowedDisciplines == nil)

    training.mode = .normal
    training.sports = [.bike, .run]
    #expect(training.constraint == .full)
    #expect(training.allowedDisciplines == ["RUN", "BIKE"])

    training.sports = [.strength, .mobility]
    #expect(training.constraint == .reduced)

    training.sports = [.mobility]
    #expect(training.constraint == .mobilityOnly)

    training.sports = []
    #expect(!training.isComplete)
}

@Test func tripTrainingReadsBackWhatTheServerStored() {
    #expect(TripTraining(constraint: .none, allowedDisciplines: []).mode == .pause)
    #expect(TripTraining(constraint: .reduced, allowedDisciplines: nil).mode == .lighter)
    #expect(TripTraining(constraint: .mobilityOnly, allowedDisciplines: []).sports == [.mobility])

    let derived = TripTraining(constraint: .reduced, allowedDisciplines: ["STRENGTH"])
    #expect(derived.mode == .normal)
    #expect(derived.sports == [.strength])
}

@Test func tripNeedsAPlaceAndConstraintATitle() {
    var trip = MemoryEntryDraft(type: .travel)
    trip.title = "Déplacement pro"
    #expect(!trip.isComplete)
    trip.location = "L"
    #expect(!trip.isComplete)
    trip.location = "Lyon"
    #expect(trip.isComplete)

    var constraint = MemoryEntryDraft(type: .constraint)
    #expect(!constraint.isComplete)
    constraint.title = "Semaine chargée"
    #expect(constraint.isComplete)
}

@Test func tripEndingBeforeItStartsIsNotComplete() {
    var trip = MemoryEntryDraft(type: .travel)
    trip.location = "Lyon"
    trip.endDay = Calendar.current.date(byAdding: .day, value: -1, to: trip.startDay) ?? trip.startDay
    #expect(!trip.isComplete)
}

@Test func draftKeepsTheServerDayInAnyTimeZone() throws {
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    let midnight = try #require(utc.date(from: DateComponents(year: 2026, month: 11, day: 2)))
    let entry = CoachMemoryEntry(type: .travel, locationLabel: "Lyon", startDate: midnight, endDate: midnight)

    let input = MemoryEntryDraft(entry: entry, calendar: newYork).input(calendar: newYork)

    #expect(utc.component(.day, from: input.startDate) == 2)
    #expect(utc.component(.day, from: input.endDate) == 2)
    #expect(entry.formattedDateRange.hasPrefix("2 "))
}

@Test func tripKeepsItsTitleUnlessThePlaceChanges() {
    let entry = CoachMemoryEntry(type: .travel, label: "Stage", locationLabel: "Lyon", startDate: Date(), endDate: Date())
    var draft = MemoryEntryDraft(entry: entry)
    #expect(draft.input().label == "Stage")
    draft.location = "Nice"
    #expect(draft.input().label == nil)
}

@MainActor
@Test func refusedCreationIsNotMistakenForAnEarlierEntry() async {
    let existing = CoachMemoryEntry(type: .travel, locationLabel: "Lyon", startDate: Date(), endDate: Date())
    let client = RefusingCoachMemoryClient(snapshot: CoachMemorySnapshot(entries: [existing]))
    let store = CoachMemoryStore(client: client, tokenProvider: { "token" })
    var draft = MemoryEntryDraft(type: .travel)
    draft.location = "Nice"

    let saved = await store.createEntry(draft.input())

    #expect(!saved)
    #expect(store.errorMessage == "Un lieu est requis pour un déplacement.")
}

@MainActor
@Test func updateReplacesTheEntry() async {
    let existing = CoachMemoryEntry(id: "a", type: .travel, locationLabel: "Lyon", startDate: Date(), endDate: Date())
    let client = StubCoachMemoryClient(stubbedSnapshot: CoachMemorySnapshot(entries: [existing]))
    let store = CoachMemoryStore(client: client, tokenProvider: { "token" })
    await store.load()
    var draft = MemoryEntryDraft(entry: existing)
    draft.location = "Nice"

    let saved = await store.updateEntry(id: "a", draft.input())

    #expect(saved)
    #expect(store.entries.map(\.locationLabel) == ["Nice"])
}

@Test func scheduleSplitsTripsOnTodayAndLeavesTheRestToTheMemory() throws {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    func day(_ value: Int) throws -> Date {
        try #require(utc.date(from: DateComponents(year: 2026, month: 11, day: value)))
    }
    let now = CoachMemoryEntry(id: "now", type: .travel, locationLabel: "Lyon", startDate: try day(1), endDate: try day(5))
    let next = CoachMemoryEntry(id: "next", type: .constraint, label: "Boulot", startDate: try day(9), endDate: try day(10))
    let injury = CoachMemoryEntry(id: "injury", type: .injury, label: "Genou", startDate: try day(1), endDate: try day(5))

    let schedule = PlanTravel.schedule([next, injury, now], today: try day(3), calendar: utc)

    #expect(schedule.current.map(\.id) == ["now"])
    #expect(schedule.upcoming.map(\.id) == ["next"])
    #expect(!schedule.isEmpty)
    #expect(PlanTravel.schedule([injury], today: try day(3), calendar: utc).isEmpty)
}

private final class RefusingCoachMemoryClient: CoachMemoryServing, @unchecked Sendable {
    let stored: CoachMemorySnapshot
    init(snapshot: CoachMemorySnapshot) { stored = snapshot }

    func snapshot(token: String) async throws -> CoachMemorySnapshot { stored }
    func saveProfileContext(_ context: String, token: String) async throws {}
    func createEntry(_ input: CreateCoachMemoryInput, token: String) async throws -> CoachMemoryEntry {
        throw SharpitAPIError.message("Un lieu est requis pour un déplacement.")
    }
    func updateEntry(id: String, _ input: CreateCoachMemoryInput, token: String) async throws -> CoachMemoryEntry {
        throw SharpitAPIError.message("Refus")
    }
    func deleteEntry(id: String, token: String) async throws {}
}
