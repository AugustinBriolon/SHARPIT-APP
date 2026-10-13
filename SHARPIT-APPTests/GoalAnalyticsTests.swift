import Foundation
import Testing
@testable import Sharpit

@Test func volumeStatsAggregatesDoneSessionsAndDurations() {
    let goalId = "goal_half_1"
    let created = Date(timeIntervalSince1970: 1721147257) // 2026-07-16
    let goal = V1Goal(
        id: goalId,
        title: "Half IronMan Versailles",
        kind: .race,
        targetPerformance: "Sub 6h",
        createdAt: created
    )

    // Build 51 done sessions (13 bike, 19 strength, 6 swim, 13 run) totaling 129510s = 35h58
    var sessions: [V1PlannedSessionItem] = []
    let sessionDate = created.addingTimeInterval(86400)

    // 13 Bike sessions totaling 54835s
    for i in 0..<13 {
        let dur = i == 12 ? (54835.0 - 12 * 4200.0) : 4200.0
        sessions.append(V1PlannedSessionItem(
            id: "bike_\(i)",
            date: sessionDate,
            type: "BIKE",
            goalId: goalId,
            completed: true,
            activity: V1PlannedSessionActivitySummary(id: "act_bike_\(i)", duration: dur, type: "BIKE")
        ))
    }

    // 13 Run sessions totaling 34643s
    for i in 0..<13 {
        let dur = i == 12 ? (34643.0 - 12 * 2660.0) : 2660.0
        sessions.append(V1PlannedSessionItem(
            id: "run_\(i)",
            date: sessionDate,
            type: "RUN",
            goalId: goalId,
            completed: true,
            activity: V1PlannedSessionActivitySummary(id: "act_run_\(i)", duration: dur, type: "RUN")
        ))
    }

    // 19 Strength sessions totaling 30207s
    for i in 0..<19 {
        let dur = i == 18 ? (30207.0 - 18 * 1590.0) : 1590.0
        sessions.append(V1PlannedSessionItem(
            id: "strength_\(i)",
            date: sessionDate,
            type: "STRENGTH",
            goalId: goalId,
            completed: true,
            activity: V1PlannedSessionActivitySummary(id: "act_strength_\(i)", duration: dur, type: "STRENGTH")
        ))
    }

    // 6 Swim sessions totaling 9825s
    for i in 0..<6 {
        let dur = i == 5 ? (9825.0 - 5 * 1637.0) : 1637.0
        sessions.append(V1PlannedSessionItem(
            id: "swim_\(i)",
            date: sessionDate,
            type: "SWIM",
            goalId: goalId,
            completed: true,
            activity: V1PlannedSessionActivitySummary(id: "act_swim_\(i)", duration: dur, type: "SWIM")
        ))
    }

    // Add an unrelated session for another goal (should be ignored)
    sessions.append(V1PlannedSessionItem(
        id: "other_1",
        date: sessionDate,
        type: "RUN",
        goalId: "other_goal",
        completed: true,
        activity: V1PlannedSessionActivitySummary(id: "act_other_1", duration: 3600, type: "RUN")
    ))

    // Add an uncompleted session for this goal (should be ignored)
    sessions.append(V1PlannedSessionItem(
        id: "future_1",
        date: sessionDate,
        type: "BIKE",
        goalId: goalId,
        completed: false
    ))

    let stats = GoalAnalyticsEngine.computeVolumeStats(goal: goal, sessions: sessions)

    #expect(stats.sessionsDone == 51)
    #expect(stats.durationSeconds == 129510.0)
    #expect(stats.durationLabel == "35h58")
    #expect(stats.topSportLabel == "Vélo")
    #expect(stats.sessionHint == "Mix : Vélo en tête")
    #expect(stats.durationHint == "Mix : Vélo en tête")
}

@Test func goalDecodesCreatedAtAndCalculatesPhase() throws {
    let json = """
    {
        "id": "goal_test_1",
        "title": "Half IronMan Versailles",
        "kind": "RACE",
        "priority": "A",
        "targetDate": "2026-10-11T00:00:00.000Z",
        "targetPerformance": "Sub 6h",
        "createdAt": "2026-07-16T16:27:37.196Z",
        "achieved": false
    }
    """
    let goal = try JSONDecoder().decode(V1Goal.self, from: Data(json.utf8))
    #expect(goal.id == "goal_test_1")
    #expect(goal.createdAt != nil)

    // Verify countdown text helper
    if let cd = goal.countdownText {
        #expect(cd.contains("jours restants") || cd.contains("J-") || cd.contains("Jour J") || cd.contains("passée"))
    }
}

@Test func aReachedRaceCountsItsPreparationFromActivitiesWhenNoSessionIsTied() {
    let day: TimeInterval = 86_400
    let race = Date(timeIntervalSince1970: 1_800_000_000)
    let goal = V1Goal(id: "g", title: "Half", kind: .race, targetDate: race, achieved: true, createdAt: race - 60 * day)
    let activities = [
        V1ActivityListItem(type: .bike, date: race - 30 * day, duration: 7_200),
        V1ActivityListItem(type: .run, date: race - 10 * day, duration: 3_600),
        V1ActivityListItem(type: .triathlon, date: race + 3_600, duration: 20_403),
        V1ActivityListItem(type: .run, date: race + 5 * day, duration: 2_400),   // after the race: next block
        V1ActivityListItem(type: .run, date: race - 90 * day, duration: 2_400),  // before the goal existed
    ]
    let stats = GoalAnalyticsEngine.computeVolumeStats(goal: goal, sessions: [], activities: activities, now: race + 7 * day)
    #expect(stats.sessionsDone == 3)
    #expect(stats.durationSeconds == 31_203)
    #expect(stats.topSportLabel == "Triathlon")
}
