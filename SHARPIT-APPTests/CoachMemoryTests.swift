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

    func saveProfileContext(_ context: String, token: String) async throws {}

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

