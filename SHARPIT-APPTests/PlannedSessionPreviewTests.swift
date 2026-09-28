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

// MARK: - Breakdown fetched for Today's line

private func plannedItems() throws -> [V1PlannedSessionItem] {
    let json = """
    [
      { "id": "a", "date": "2026-09-21T00:00:00.000Z", "title": "Vélo", "type": "BIKE",
        "breakdown": { "steps": [], "derived": true, "warnings": [] } },
      { "id": "b", "date": "2026-09-21T00:00:00.000Z", "title": "Renfo", "type": "STRENGTH",
        "breakdown": { "steps": [{ "key": "s1", "label": "Squat", "detail": "4 × 8", "target": null, "repeat": 1, "notes": null }],
                       "derived": false, "warnings": [] } }
    ]
    """
    return try JSONDecoder().decode([V1PlannedSessionItem].self, from: Data(json.utf8))
}

/// Today's line carries no prescription; the drawer finds it among the day's sessions.
@Test func theBreakdownOfTodaysLineIsFoundAmongTheDaysSessions() throws {
    let sessions = try plannedItems()
    #expect(PlannedSessionPreview.breakdown(of: "b", in: sessions)?.steps.map(\.label) == ["Squat"])
    #expect(PlannedSessionPreview.breakdown(of: "a", in: sessions) == nil)
    #expect(PlannedSessionPreview.breakdown(of: "missing", in: sessions) == nil)
}

// MARK: - Repeated sets

@Test func aBlockAndItsRecoveryRepeatAsOneSet() {
    let sets = PlannedStepSet.sets(from: [
        V1PlannedSessionStep(key: "0-0", label: "Échauffement", group: "0"),
        V1PlannedSessionStep(key: "1-0", label: "Bloc", group: "1", repeatCount: 5),
        V1PlannedSessionStep(key: "1-1", label: "Récup", group: "1", repeatCount: 5),
        V1PlannedSessionStep(key: "2-0", label: "Retour au calme", group: "2"),
    ])

    #expect(sets.map(\.repeatCount) == [1, 5, 1])
    #expect(sets[1].steps.map(\.label) == ["Bloc", "Récup"])
}

@Test func aBreakdownReadBeforeGroupsKeepsItsRepeatedBlockTogether() {
    // No `group` on the wire: the block half of the key still pairs a repeated block.
    let sets = PlannedStepSet.sets(from: [
        V1PlannedSessionStep(key: "0-0", label: "Échauffement"),
        V1PlannedSessionStep(key: "1-0", label: "Bloc", repeatCount: 4),
        V1PlannedSessionStep(key: "1-1", label: "Récup", repeatCount: 4),
    ])

    #expect(sets.count == 2)
    #expect(sets[1].steps.count == 2)
}

@Test func strengthSetsWithoutGroupsStayApart() {
    let sets = PlannedStepSet.sets(from: [
        V1PlannedSessionStep(key: "strength-0", label: "Squat", detail: "4 × 8"),
        V1PlannedSessionStep(key: "strength-1", label: "Fentes", detail: "3 × 10"),
    ])

    #expect(sets.count == 2)
}

@Test func aGroupSentByTheServerIsDecoded() throws {
    let json = #"{ "key": "1-0", "label": "Bloc", "group": "1", "repeat": 5 }"#
    let step = try JSONDecoder().decode(V1PlannedSessionStep.self, from: Data(json.utf8))

    #expect(step.group == "1")
    #expect(step.repeatCount == 5)
}

// MARK: - Bricks

@Test func aTodayBrickLineOpensAsItsLegsAndReadsThemFromThePlan() {
    let card = SessionCardModel(
        id: "brick-group", kind: .planned, title: "Brick · Vélo → Course", subtitle: nil, metrics: [],
        sport: "Triathlon", priority: true, plannedSessionId: "bike",
        brickLegs: [
            V1TodayBrickLeg(id: "bike", type: "BIKE", title: "Vélo", durationMin: 60),
            V1TodayBrickLeg(id: "run", type: "RUN", title: "Course", durationMin: 20),
        ]
    )
    let brick = PlannedBrickPreview(card: card, date: nil)

    #expect(brick?.chain == "Vélo → Course")
    #expect(brick?.totalDurationMin == 80)

    let step = V1PlannedSessionStep(key: "0-0", label: "Bloc")
    let plan = [
        V1PlannedSessionItem(id: "run", date: .now, title: "Course", type: "RUN", durationMin: 20,
                             breakdown: V1PlannedSessionBreakdown(steps: [step])),
        V1PlannedSessionItem(id: "bike", date: .now, title: "Vélo", type: "BIKE", durationMin: 60,
                             breakdown: V1PlannedSessionBreakdown(steps: [step])),
    ]
    let refreshed = brick?.refreshed(from: plan)
    #expect(refreshed?.legs.map(\.sessionId) == ["bike", "run"])
    #expect(refreshed?.legs.allSatisfy { !$0.steps.isEmpty } == true)
    // A leg gone from the plan: the drawer keeps what it had rather than half a brick.
    #expect(brick?.refreshed(from: [plan[0]]) == nil)
}

@Test func aPlainTodayLineIsNoBrick() {
    let card = SessionCardModel(
        id: "s1", kind: .planned, title: "Seuil", subtitle: nil, metrics: [], sport: "Course",
        priority: true, plannedSessionId: "s1"
    )

    #expect(PlannedBrickPreview(card: card, date: nil) == nil)
}
