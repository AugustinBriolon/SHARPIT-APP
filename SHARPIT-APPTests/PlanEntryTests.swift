import Foundation
import Testing
@testable import Sharpit

private let calendar = Calendar(identifier: .gregorian)
private let now = Date(timeIntervalSince1970: 1_789_000_000)
private var today: Date { calendar.startOfDay(for: now) }
private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today)! }
private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today)! }

private func planned(_ id: String, on date: Date) -> V1PlannedSessionItem {
    V1PlannedSessionItem(id: id, date: date, title: "Prévu \(id)", type: "RUN")
}

/// Built by decoding, because the wire types are `Decodable` only — which also keeps the
/// fixture honest about the shape the API actually sends.
private func activity(
    _ id: String,
    on date: Date,
    plannedId: String? = nil,
    score: Double? = nil
) -> V1ActivityListItem {
    var fields: [String] = [
        "\"id\": \"\(id)\"",
        "\"type\": \"RUN\"",
        "\"date\": \"\(ISO8601DateFormatter().string(from: date))\"",
        "\"title\": \"Réalisé \(id)\"",
        "\"duration\": 3600",
    ]
    if let plannedId {
        let analysis = score.map { "\"analysis\": { \"complianceScore\": \($0) }" } ?? "\"analysis\": null"
        fields.append(
            "\"plannedSession\": { \"id\": \"\(plannedId)\", \"title\": \"Prévu \(plannedId)\", \(analysis) }"
        )
    }
    let json = "{ \(fields.joined(separator: ", ")) }"

    do {
        return try JSONDecoder().decode(V1ActivityListItem.self, from: Data(json.utf8))
    } catch {
        fatalError("fixture does not match V1ActivityListItem: \(error)")
    }
}

private func entries(
    planned sessions: [V1PlannedSessionItem] = [],
    activities: [V1ActivityListItem] = []
) -> [PlanEntry] {
    PlanEntryBuilder.entries(
        planned: sessions,
        activities: activities,
        now: now,
        calendar: calendar
    )
}

@Test func anActivityAbsorbsThePlannedSessionItWasRecordedAgainst() {
    // Showing both would claim the athlete owed two sessions when they owed one.
    let result = entries(
        planned: [planned("p1", on: yesterday)],
        activities: [activity("a1", on: yesterday, plannedId: "p1", score: 82)]
    )

    #expect(result.count == 1)
    guard case .executed(let executed) = result[0] else {
        Issue.record("expected the activity to replace its prescription")
        return
    }
    #expect(executed.activity.id == "a1")
    #expect(executed.complianceScore == 82)
    #expect(executed.wasPlanned)
}

@Test func anActivityWithNoPlanIsShownOnItsOwn() {
    let result = entries(activities: [activity("a1", on: yesterday)])

    guard case .executed(let executed) = result[0] else {
        Issue.record("expected an executed entry")
        return
    }
    #expect(executed.wasPlanned == false)
    #expect(executed.complianceScore == nil)
}

@Test func aPastPrescriptionWithNothingRecordedReadsAsMissed() {
    let result = entries(planned: [planned("p1", on: yesterday)])

    guard case .missed(let session) = result[0] else {
        Issue.record("expected a missed entry")
        return
    }
    #expect(session.id == "p1")
}

@Test func todayAndLaterStayPrescriptions() {
    let result = entries(planned: [planned("p1", on: today), planned("p2", on: tomorrow)])

    #expect(result.allSatisfy { if case .planned = $0 { true } else { false } })
    #expect(result.count == 2)
}

@Test func anUnrelatedActivityDoesNotAbsorbAPrescription() {
    // Same day, no link: the athlete did something else and still owes the session.
    let result = entries(
        planned: [planned("p1", on: yesterday)],
        activities: [activity("a1", on: yesterday)]
    )

    #expect(result.count == 2)
    #expect(result.contains { if case .missed = $0 { true } else { false } })
    #expect(result.contains { if case .executed = $0 { true } else { false } })
}

@Test func oneActivityAbsorbsOnlyItsOwnPrescription() {
    let result = entries(
        planned: [planned("p1", on: yesterday), planned("p2", on: yesterday)],
        activities: [activity("a1", on: yesterday, plannedId: "p1")]
    )

    #expect(result.count == 2)
    let missed = result.compactMap { entry -> V1PlannedSessionItem? in
        guard case .missed(let session) = entry else { return nil }
        return session
    }
    #expect(missed.map(\.id) == ["p2"])
}

@Test func entriesComeBackInChronologicalOrder() {
    let result = entries(
        planned: [planned("p2", on: tomorrow)],
        activities: [activity("a1", on: yesterday)]
    )

    #expect(result.map(\.date) == result.map(\.date).sorted())
}

@Test func anExecutedEntryWithoutAnalysisStillCountsAsPlanned() {
    // The link exists, the analysis has not run yet: it came from the plan even without
    // a score, so the row must not read as an unplanned session.
    let result = entries(
        planned: [planned("p1", on: yesterday)],
        activities: [activity("a1", on: yesterday, plannedId: "p1")]
    )

    guard case .executed(let executed) = result[0] else {
        Issue.record("expected an executed entry")
        return
    }
    #expect(executed.wasPlanned)
    #expect(executed.complianceScore == nil)
}

@Test func everyEntryCarriesAStableIdentity() {
    let result = entries(
        planned: [planned("p1", on: tomorrow), planned("p2", on: yesterday)],
        activities: [activity("a1", on: yesterday)]
    )

    #expect(Set(result.map(\.id)).count == result.count)
}

@Test func aPlannedSessionWithActivityIdIsAbsorbedEvenIfActivityHasNoBacklink() {
    // When the planned session was linked on server (activityId or completed set),
    // it must not appear as missed/planned even if the activity didn't carry the link yet.
    let linkedPlanned = V1PlannedSessionItem(
        id: "p1",
        date: yesterday,
        title: "Sortie longue",
        type: "RUN",
        completed: true,
        activityId: "a1"
    )
    let plainActivity = activity("a1", on: yesterday)

    let result = entries(
        planned: [linkedPlanned],
        activities: [plainActivity]
    )

    #expect(result.count == 1)
    guard case .executed(let executed) = result[0] else {
        Issue.record("expected executed entry")
        return
    }
    #expect(executed.wasPlanned)
    #expect(executed.plannedTitle == "Sortie longue")
}


// MARK: - Bricks

private func leg(_ id: String, on date: Date, brick: String, order: Int, type: String, minutes: Int) -> V1PlannedSessionItem {
    V1PlannedSessionItem(id: id, date: date, title: id, type: type, durationMin: minutes, brickGroupId: brick, brickOrder: order)
}

@Test func aBricksLegsAreOneEntryInTheirOrder() {
    let result = entries(
        planned: [
            leg("run", on: tomorrow, brick: "b1", order: 1, type: "RUN", minutes: 20),
            planned("solo", on: tomorrow),
            leg("bike", on: tomorrow, brick: "b1", order: 0, type: "BIKE", minutes: 60),
        ],
        activities: []
    )

    #expect(result.count == 2)
    guard let brick = result.lazy.compactMap({ entry -> PlanBrick? in
        if case .brick(let brick) = entry { brick } else { nil }
    }).first else {
        Issue.record("expected a brick entry")
        return
    }
    #expect(brick.legs.map(\.id) == ["bike", "run"])
    #expect(brick.chain == "Vélo → Course")
    #expect(brick.totalDurationMin == 80)
    #expect(!brick.isMissed)
}

@Test func aBrickWithOneLegLeftIsAPlainSession() {
    // The bike leg was done: the run left is one session, as the web demotes it.
    let bike = V1PlannedSessionItem(
        id: "bike", date: yesterday, title: "bike", type: "BIKE", completed: true, activityId: "a1",
        brickGroupId: "b1", brickOrder: 0
    )
    let result = entries(
        planned: [bike, leg("run", on: yesterday, brick: "b1", order: 1, type: "RUN", minutes: 20)],
        activities: [activity("a1", on: yesterday, plannedId: "bike")]
    )

    #expect(result.count == 2)
    #expect(result.contains { if case .missed(let session) = $0 { session.id == "run" } else { false } })
}

@Test func aBrickWhoseDayPassedReadsAsMissed() {
    let result = entries(
        planned: [
            leg("bike", on: yesterday, brick: "b1", order: 0, type: "BIKE", minutes: 60),
            leg("run", on: yesterday, brick: "b1", order: 1, type: "RUN", minutes: 20),
        ],
        activities: []
    )

    #expect(PlanDayStatus.status(of: result) == .missed)
    guard case .brick(let brick) = result.first else {
        Issue.record("expected a brick entry")
        return
    }
    #expect(brick.isMissed)
    #expect(result.first?.selection == .brick(brick))
}
