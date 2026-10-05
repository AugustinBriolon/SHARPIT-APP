import Foundation
import Testing
@testable import Sharpit

private nonisolated let zonesJSON = """
{
  "apiVersion": 1,
  "bodyParts": ["Genou", "Ischio", "Épaule"],
  "zones": [
    {
      "id": "n1", "title": "Nerf sciatique", "category": "PAIN", "categoryLabel": "Douleur",
      "bodyPart": "Ischio", "bodyPartRecognized": true, "side": "LEFT", "sideLabel": "Gauche",
      "status": "ACTIVE", "statusLabel": "Active", "severity": 0, "functionalImpact": null,
      "functionalImpactLabel": null, "description": null, "affectsTraining": true,
      "startDate": "2026-01-01T00:00:00.000Z", "resolvedAt": null,
      "strategy": "progressive", "strategyLabel": "Reprise progressive",
      "strategyDetail": "Elle peut être sollicitée.", "resolutionSuggested": true,
      "recurrenceCount": 1, "followUpQuestion": null, "upcomingSessionsLoading": 0,
      "timeline": [
        { "id": "c3", "date": "2026-10-03T00:00:00.000Z", "kind": "reading", "label": "Douleur 0/10",
          "severity": 0, "functionalImpact": "NONE", "comment": null },
        { "id": "c2", "date": "2026-09-20T00:00:00.000Z", "kind": "status", "label": "Rechute",
          "severity": null, "functionalImpact": null, "comment": null },
        { "id": "c1", "date": "2026-09-01T00:00:00.000Z", "kind": "reading", "label": "Douleur 3/10",
          "severity": 3, "functionalImpact": null, "comment": "Après la sortie longue" }
      ]
    },
    {
      "id": "n2", "title": "Épaules enroulées", "category": "POSTURE", "categoryLabel": "Posture",
      "bodyPart": "Épaule", "side": "BILATERAL", "sideLabel": "Bilatéral", "status": "ACTIVE",
      "statusLabel": "Active", "severity": 5, "affectsTraining": true,
      "startDate": "2026-09-01T00:00:00.000Z", "strategy": "correct", "strategyLabel": "À corriger",
      "strategyDetail": "Le renfo la travaille.", "timeline": []
    },
    {
      "id": "n3", "title": "Tendinite", "category": "INJURY", "categoryLabel": "Blessure",
      "bodyPart": "Achille", "side": "NA", "sideLabel": null, "status": "RESOLVED",
      "statusLabel": "Résolue", "severity": 0, "affectsTraining": true,
      "startDate": "2026-03-01T00:00:00.000Z", "resolvedAt": "2026-04-01T00:00:00.000Z",
      "strategy": "something_new", "strategyLabel": "?", "strategyDetail": "?", "timeline": []
    },
    { "id": "broken" }
  ]
}
"""

private nonisolated func decodedZones() throws -> V1SensitiveZones {
    try JSONDecoder().decode(V1SensitiveZones.self, from: Data(zonesJSON.utf8))
}

@Suite struct SensitiveZonesDecodingTests {
    @Test func readsZonesAndDropsWhatItCannot() throws {
        let zones = try decodedZones()
        #expect(zones.zones.map(\.id) == ["n1", "n2", "n3"])
        #expect(zones.open.map(\.id) == ["n1", "n2"])
        #expect(zones.resolved.map(\.id) == ["n3"])
        #expect(zones.bodyParts == ["Genou", "Ischio", "Épaule"])
    }

    @Test func readsTheFollowUpState() throws {
        let sciatica = try #require(try decodedZones().zones.first)
        #expect(sciatica.strategy == .progressive)
        #expect(sciatica.resolutionSuggested)
        #expect(sciatica.recurrenceCount == 1)
        #expect(sciatica.place == "Ischio · Gauche")
        #expect(sciatica.timeline.map(\.kind) == [.reading, .status, .reading])
        // Oldest first, readings only, for the curve.
        #expect(sciatica.readings.map(\.severity) == [3, 0])
    }

    @Test func toleratesMissingFieldsAndUnknownStrategies() throws {
        let zones = try decodedZones().zones
        #expect(zones[1].bodyPartRecognized)
        #expect(zones[1].resolutionSuggested == false)
        #expect(zones[2].strategy == .none)
        #expect(zones[2].resolvedAt != nil)
        #expect(zones[2].place == "Achille")
    }
}

@Suite struct SensitiveZoneDraftTests {
    @Test func namesTheZoneWhenTheAthleteDoesNot() {
        var draft = SensitiveZoneDraft()
        #expect(!draft.isComplete)
        draft.bodyPart = "Genou"
        #expect(draft.isComplete)
        #expect(draft.resolvedTitle == "Douleur · Genou")
        draft.title = "  Tendinite rotulienne "
        #expect(draft.createInput.title == "Tendinite rotulienne")
    }

    @Test func keepsAFreeTextRegion() {
        var draft = SensitiveZoneDraft()
        draft.customBodyPart = " Plexus "
        #expect(draft.createInput.bodyPart == "Plexus")
    }

    @Test func patchesOnlyWhatChanged() throws {
        let zone = try #require(try decodedZones().zones.first)
        var draft = SensitiveZoneDraft(zone: zone, offered: ["Ischio"])
        #expect(draft.bodyPart == "Ischio")
        #expect(draft.patch(from: zone) == PhysicalNotePatch())
        draft.severity = 2
        draft.functionalImpact = "MILD"
        #expect(draft.patch(from: zone) == PhysicalNotePatch(severity: 2, functionalImpact: "MILD"))
    }

    @Test func aCheckInNeedsAReading() {
        var draft = ZoneCheckinDraft()
        #expect(draft.input == nil)
        draft.severity = 0
        draft.comment = "  "
        #expect(draft.input == PhysicalCheckinInput(severity: 0, functionalImpact: nil, comment: nil))
    }

    @Test func offersTheStatusChangesThatMakeSense() {
        #expect(ZoneStatusAction.available(for: "ACTIVE") == [.monitor, .resolve])
        #expect(ZoneStatusAction.available(for: "MONITORING") == [.resume, .resolve])
        #expect(ZoneStatusAction.available(for: "RESOLVED").isEmpty)
    }
}

@Suite struct SensitiveZoneReadoutTests {
    @Test func summarisesWhatTheOpenZonesDoToThePlan() throws {
        let zones = try decodedZones().zones
        #expect(SensitiveZoneReadout.summary(zones) == "1 en reprise · 1 à corriger")
        #expect(SensitiveZoneReadout.summary([zones[2]]) == nil)
    }

    @Test func asksToCloseASilentZoneFirst() throws {
        let zones = try decodedZones().zones
        #expect(SensitiveZoneReadout.prompt(zones) == "« Nerf sciatique » ne fait plus mal : c'est résolu ?")
        #expect(SensitiveZoneReadout.prompt([zones[1]]) == nil)
    }

    @Test func wordsCounts() {
        #expect(SensitiveZoneReadout.upcoming(0) == nil)
        #expect(SensitiveZoneReadout.upcoming(2) == "2 séances à venir la sollicitent")
        #expect(SensitiveZoneReadout.relapses(1) == "1 rechute")
        #expect(SensitiveZoneReadout.severity(nil) == "—")
    }
}

private actor ZoneClient: SensitiveZoneServing {
    private(set) var reads = 0
    private(set) var patches: [(String, PhysicalNotePatch)] = []
    private(set) var checkins: [PhysicalCheckinInput] = []
    private(set) var created: [CreatePhysicalNoteInput] = []
    private let refusesWrites: Bool

    init(refusesWrites: Bool = false) { self.refusesWrites = refusesWrites }

    func sensitiveZonesData(token _: String) async throws -> Data {
        reads += 1
        return Data(zonesJSON.utf8)
    }

    func updateNote(id: String, patch: PhysicalNotePatch, token _: String) async throws {
        if refusesWrites { throw SharpitAPIError.unauthorized }
        patches.append((id, patch))
    }

    func addCheckin(noteId _: String, input: PhysicalCheckinInput, token _: String) async throws {
        checkins.append(input)
    }

    func createNote(_ input: CreatePhysicalNoteInput, token _: String) async throws {
        created.append(input)
    }
}

@MainActor
@Suite struct SensitiveZonesStoreTests {
    @Test func resolvingSendsTheStatusThenReadsTheZonesAgain() async throws {
        let client = ZoneClient()
        let store = SensitiveZonesStore(client: client, tokenProvider: { "t" })
        await store.load()
        let zone = try #require(store.zone("n1"))

        #expect(await store.setStatus(zone, to: "RESOLVED"))
        let patches = await client.patches
        #expect(patches.first?.0 == "n1")
        #expect(patches.first?.1 == PhysicalNotePatch(status: "RESOLVED"))
        #expect(await client.reads == 2)
    }

    @Test func aCheckInAndADeclarationGoOut() async throws {
        let client = ZoneClient()
        let store = SensitiveZonesStore(client: client, tokenProvider: { "t" })
        await store.load()
        let zone = try #require(store.zone("n2"))
        var checkin = ZoneCheckinDraft()
        checkin.severity = 4
        #expect(await store.checkin(zone, checkin))
        var draft = SensitiveZoneDraft()
        draft.bodyPart = "Genou"
        #expect(await store.declare(draft))
        #expect(await client.checkins.map(\.severity) == [4])
        #expect(await client.created.map(\.bodyPart) == ["Genou"])
    }

    @Test func anEditWithNothingChangedSendsNothing() async throws {
        let client = ZoneClient()
        let store = SensitiveZonesStore(client: client, tokenProvider: { "t" })
        await store.load()
        let zone = try #require(store.zone("n1"))
        #expect(await store.update(zone, with: SensitiveZoneDraft(zone: zone, offered: ["Ischio"])))
        #expect(await client.patches.isEmpty)
    }

    @Test func aLostSessionSaysSo() async throws {
        let store = SensitiveZonesStore(client: ZoneClient(refusesWrites: true), tokenProvider: { "t" })
        await store.load()
        let zone = try #require(store.zone("n1"))
        #expect(await store.setStatus(zone, to: "MONITORING") == false)
        #expect(store.phase == .unauthorized)
    }
}
