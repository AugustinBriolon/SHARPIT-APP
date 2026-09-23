import Foundation
import Testing
@testable import Sharpit

@Test func targetSecondsParsesFormatsCorrectly() {
    #expect(GoalAnalyticsEngine.parseTargetSeconds("Sub 6h") == 21600)
    #expect(GoalAnalyticsEngine.parseTargetSeconds("Sous 6h") == 21600)
    #expect(GoalAnalyticsEngine.parseTargetSeconds("6h") == 21600)
    #expect(GoalAnalyticsEngine.parseTargetSeconds("1h30") == 5400)
    #expect(GoalAnalyticsEngine.parseTargetSeconds("Sub 1h30") == 5400)
    #expect(GoalAnalyticsEngine.parseTargetSeconds("3:15:00") == 11700)
    #expect(GoalAnalyticsEngine.parseTargetSeconds("45:00") == 2700)
    #expect(GoalAnalyticsEngine.parseTargetSeconds(nil) == nil)
    #expect(GoalAnalyticsEngine.parseTargetSeconds("") == nil)
}

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

@Test func triathlonProjectionCalculatesAccurateFinishForHalfIronman() {
    let goal = V1Goal(
        id: "goal_half_1",
        title: "Half IronMan Versailles",
        kind: .race,
        raceFormat: "HALF IRON MAN",
        targetPerformance: "Sub 6h"
    )

    let profile = V1AthleteProfile(
        ftpW: 207,
        runThresholdPaceSecPerKm: 306.0,
        swimCssSecPer100m: 103.5
    )

    let proj = GoalAnalyticsEngine.computeRaceProjection(goal: goal, profile: profile)
    #expect(proj != nil)

    guard let p = proj else { return }
    // 5:14:02 corresponds to 18842 seconds
    #expect(p.projectedSeconds >= 18800 && p.projectedSeconds <= 18900)
    #expect(p.projectedLabel.starts(with: "5:14:"))
    #expect(p.targetLabel == "Sub 6h")
    #expect(p.isAhead)
    #expect(p.gapLabel.contains("sous la cible"))
    #expect(p.segments.count == 5)
    #expect(p.segments.map(\.kind) == ["swim", "t1", "bike", "t2", "run"])
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
