import Foundation
import Testing
@testable import Sharpit

@Test func aPlannedSessionReadsWhetherItIsKey() throws {
    let key = try JSONDecoder().decode(
        V1PlannedSessionItem.self,
        from: Data(#"{"id":"s1","date":"2026-10-06T00:00:00.000Z","isKey":true}"#.utf8)
    )
    let older = try JSONDecoder().decode(
        V1PlannedSessionItem.self,
        from: Data(#"{"id":"s2","date":"2026-10-06T00:00:00.000Z"}"#.utf8)
    )
    #expect(key.isKey)
    #expect(!older.isKey)
}

@Test func aProposedSessionReadsTheKeyTheServerMarked() throws {
    let json = #"{"dayOffset":1,"date":"2026-10-06","type":"RUN","intensity":"THRESHOLD","title":"Seuil","description":"","durationMin":50,"load":70,"key":true}"#
    let session = try JSONDecoder().decode(V1GeneratedSession.self, from: Data(json.utf8))
    #expect(session.isKey)
}

@Test func aBrickIsKeyWhenALegIs() {
    let legs = [
        V1PlannedSessionItem(id: "l1", date: .now, type: "BIKE", brickGroupId: "b1", brickOrder: 0, isKey: true),
        V1PlannedSessionItem(id: "l2", date: .now, type: "RUN", brickGroupId: "b1", brickOrder: 1),
    ]
    #expect(PlanEntryBuilder.entries(planned: legs, activities: []).contains { entry in
        if case .brick(let brick) = entry { return brick.isKey }
        return false
    })
}

@Test func aTodayCardCarriesTheKeyFlagIntoTheDrawerPreview() {
    let card = SessionCardModel(
        id: "c1",
        kind: .planned,
        title: "Seuil",
        subtitle: nil,
        metrics: [],
        sport: "Course",
        priority: false,
        plannedSessionId: "s1",
        isKey: true
    )
    #expect(PlannedSessionPreview(card: card).isKey)
}
