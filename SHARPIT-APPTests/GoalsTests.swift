import Foundation
import Testing
@testable import Sharpit

private struct StubGoalClient: GoalServing {
    var stubbedGoals: [V1Goal] = []

    func goals(token: String) async throws -> [V1Goal] {
        stubbedGoals
    }

    func createGoal(_ input: CreateGoalInput, token: String) async throws -> V1Goal {
        V1Goal(
            id: UUID().uuidString,
            title: input.title,
            kind: input.kind,
            targetDate: input.targetDate,
            location: input.location,
            priority: input.priority
        )
    }

    func toggleAchieved(id: String, achieved: Bool, token: String) async throws -> V1Goal {
        guard var found = stubbedGoals.first(where: { $0.id == id }) else {
            throw SharpitAPIError.badRequest
        }
        found.achieved = achieved
        return found
    }

    func deleteGoal(id: String, token: String) async throws {}
}

@Test func raceGoalDecodesCorrectly() throws {
    let json = """
    {
        "id": "goal_race_1",
        "title": "Marathon de Paris",
        "kind": "RACE",
        "priority": "A",
        "targetDate": "2026-10-15T08:00:00.000Z",
        "location": "Paris, France",
        "targetPerformance": "3h15",
        "achieved": false
    }
    """
    let goal = try JSONDecoder().decode(V1Goal.self, from: Data(json.utf8))
    #expect(goal.id == "goal_race_1")
    #expect(goal.title == "Marathon de Paris")
    #expect(goal.kind == .race)
    #expect(goal.priority == .a)
    #expect(goal.location == "Paris, France")
    #expect(goal.targetPerformance == "3h15")
    #expect(!goal.achieved)
}

@Test func metricGoalComputesProgressFraction() throws {
    let goal = V1Goal(
        id: "goal_metric_1",
        title: "FTP 300W",
        kind: .metric,
        startValue: 200,
        currentValue: 250,
        targetValue: 300,
        unit: "W"
    )
    #expect(goal.progressFraction == 0.5)
}

@MainActor
@Test func goalStoreSeparatesActiveAndCompletedGoals() async {
    let client = StubGoalClient(stubbedGoals: [
        V1Goal(id: "1", title: "Course 1", kind: .race, achieved: false),
        V1Goal(id: "2", title: "Course 2", kind: .race, achieved: true),
        V1Goal(id: "3", title: "Métrique 1", kind: .metric, achieved: false)
    ])
    let store = GoalStore(client: client, tokenProvider: { "token" })
    await store.load()

    #expect(store.activeGoals.map(\.id) == ["1", "3"])
    #expect(store.completedGoals.map(\.id) == ["2"])
}

// MARK: - Ordering

private func race(_ title: String, inDays days: Int?, priority: GoalPriority? = nil, achieved: Bool = false) -> V1Goal {
    V1Goal(
        id: title,
        title: title,
        kind: .race,
        targetDate: days.map { Calendar.current.date(byAdding: .day, value: $0, to: Date())! },
        achieved: achieved,
        priority: priority
    )
}

@Test func theNextRaceIsTheNearestARaceAhead() {
    let goals = [
        race("B proche", inDays: 10, priority: .b),
        race("A lointaine", inDays: 90, priority: .a),
        race("A passée", inDays: -3, priority: .a),
        race("A atteinte", inDays: 20, priority: .a, achieved: true),
    ]

    #expect(GoalOrdering.nextRace(in: goals)?.title == "A lointaine")
}

@Test func withoutAnARaceTheNearestRaceLeads() {
    let goals = [race("C", inDays: 40, priority: .c), race("B", inDays: 12, priority: .b)]

    #expect(GoalOrdering.nextRace(in: goals)?.title == "B")
    #expect(GoalOrdering.nextRace(in: [race("Passée", inDays: -1)]) == nil)
}

@Test func activeGoalsReadSoonestFirstThenUndated() {
    let goals = [race("Sans date", inDays: nil), race("Loin", inDays: 60), race("Proche", inDays: 5)]

    #expect(GoalOrdering.active(goals).map(\.title) == ["Proche", "Loin", "Sans date"])
}
