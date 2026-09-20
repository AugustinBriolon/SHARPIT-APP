import Foundation
import Testing
@testable import Sharpit

// Plan and Today show the same object from two screens, so both map into one preview
// rather than each growing its own drawer.

@Test func aPlanSessionCarriesItsPrescriptionIntoThePreview() {
    let session = V1PlannedSessionItem(
        id: "ps-1",
        date: Date(timeIntervalSince1970: 1_789_000_000),
        title: "Seuil 40 min",
        type: "RUN",
        durationMin: 40,
        intensity: "seuil",
        notes: "3 x 10 min"
    )

    let preview = PlannedSessionPreview(session: session)

    #expect(preview.sessionId == "ps-1")
    #expect(preview.title == "Seuil 40 min")
    #expect(preview.notes == "3 x 10 min")
    #expect(preview.date == session.date)
    #expect(preview.metrics.contains { $0.label == "Durée" && $0.value == "40 min" })
    #expect(preview.metrics.contains { $0.label == "Intensité" && $0.value == "Seuil" })
}

@Test func aPlanPreviewOmitsCharge() {
    // A planning number, not something the athlete acts on before a session.
    let session = V1PlannedSessionItem(
        id: "ps-1",
        date: Date(),
        type: "RUN",
        durationMin: 40,
        load: 85
    )

    #expect(PlannedSessionPreview(session: session).metrics.allSatisfy { $0.label != "Charge" })
}

@Test func aTodayCardCarriesItsPrescriptionIdNotItsLineId() {
    // A brick line is identified by its group; only `plannedSessionId` addresses the
    // session, and the drawer's coach tag depends on getting that right.
    let card = SessionCardModel(
        id: "brick-group",
        kind: .planned,
        title: "Brick · Vélo → Course",
        subtitle: "90 min",
        metrics: [V1TodayMetric(label: "Durée", value: "90", unit: "min")],
        sport: "Triathlon",
        priority: true,
        plannedSessionId: "ps-leg-1"
    )

    let preview = PlannedSessionPreview(card: card)

    #expect(preview.sessionId == "ps-leg-1")
    #expect(preview.title == "Brick · Vélo → Course")
    #expect(preview.metrics == [PlannedSessionMetric(label: "Durée", value: "90 min")])
}

@Test func aTodayCardWithoutAPrescriptionIdStillOpens() {
    // The drawer degrades: it shows what the line says and drops the coach button rather
    // than attaching a tag that names the wrong session.
    let card = SessionCardModel(
        id: "line-1",
        kind: .planned,
        title: "Séance",
        subtitle: nil,
        metrics: [],
        sport: "Course",
        priority: false,
        plannedSessionId: nil
    )

    #expect(PlannedSessionPreview(card: card).sessionId == nil)
}

@Test func aMetricWithoutAUnitIsNotPaddedWithASpace() {
    let card = SessionCardModel(
        id: "line-1",
        kind: .planned,
        title: "Séance",
        subtitle: nil,
        metrics: [V1TodayMetric(label: "Intensité", value: "Endurance", unit: "")],
        sport: "Course",
        priority: false,
        plannedSessionId: nil
    )

    #expect(PlannedSessionPreview(card: card).metrics.first?.value == "Endurance")
}

@Test func theFoldCarriesThePrescriptionIdFromTheWire() throws {
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    let fold = TodayFoldMapper.map(response)

    #expect(fold.sessions.first?.plannedSessionId == "ps-s1")
}

@Test func aPayloadWithoutThePrescriptionIdStillDecodes() throws {
    // Snapshots cached before the field existed must not fail to decode.
    var json = try #require(
        try JSONSerialization.jsonObject(with: fixtureData("full.json")) as? [String: Any]
    )
    var sessions = try #require(json["sessions"] as? [[String: Any]])
    sessions = sessions.map { session in
        var copy = session
        copy.removeValue(forKey: "plannedSessionId")
        return copy
    }
    json["sessions"] = sessions

    let response = try JSONDecoder().decode(
        V1TodayResponse.self,
        from: try JSONSerialization.data(withJSONObject: json)
    )

    #expect(response.sessions.first?.plannedSessionId == nil)
}
