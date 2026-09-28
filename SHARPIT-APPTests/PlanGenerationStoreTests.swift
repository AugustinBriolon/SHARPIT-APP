import Foundation
import Testing
@testable import Sharpit

@MainActor
private final class StreamingPlanClient: CoachPlanServing {
    private(set) var inserted: [(sessions: [V1GeneratedSession], goalId: String?)] = []
    var fails = false
    var insertFails = false

    static let week = [
        V1GeneratedSession(date: "2026-09-29", type: .run, intensity: "ENDURANCE", title: "Footing", description: "", durationMin: 45, load: 40),
        V1GeneratedSession(date: "2026-10-01", type: .bike, intensity: "TEMPO", title: "Tempo vélo", description: "", durationMin: 60, load: 55),
    ]

    func generateWeek(
        days _: Int,
        goalId _: String?,
        focus _: String?,
        startDate _: Date?,
        token _: String,
        onDraft: @escaping @Sendable ([V1GeneratedSession]) -> Void
    ) async throws -> V1GeneratedPlan {
        onDraft(Array(Self.week.prefix(1)))
        if fails { throw SharpitAPIError.server }
        return V1GeneratedPlan(summary: "Semaine", sessions: Self.week)
    }

    func adaptPlan(days _: Int, focus _: String?, token _: String, onReasoning _: @escaping @Sendable (String) -> Void) async throws -> V1AdaptPlanResult {
        V1AdaptPlanResult(summary: "", changes: [])
    }

    func insertWeek(_ sessions: [V1GeneratedSession], goalId: String?, token _: String) async throws {
        if insertFails { throw SharpitAPIError.server }
        inserted.append((sessions, goalId))
    }
}

private struct NoGoals: GoalServing {
    func goals(token _: String) async throws -> [V1Goal] { [] }
    func createGoal(_ input: CreateGoalInput, token _: String) async throws -> V1Goal { V1Goal(title: input.title, kind: input.kind) }
    func toggleAchieved(id _: String, achieved _: Bool, token _: String) async throws -> V1Goal { throw SharpitAPIError.server }
    func deleteGoal(id _: String, token _: String) async throws {}
}

@MainActor
private func settled(_ store: PlanGenerationStore) async {
    for _ in 0..<500 where store.isGenerating {
        try? await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
@Test func aGeneratedWeekComesBackReadyWithEverySessionKept() async {
    let client = StreamingPlanClient()
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), tokenProvider: { "t" })

    store.start()
    #expect(store.isGenerating)
    await settled(store)

    guard case .ready(let plan, let selected) = store.phase else {
        Issue.record("The week should be ready")
        return
    }
    #expect(plan.sessions.count == 2)
    #expect(selected == [0, 1])
}

@MainActor
@Test func onlyTheKeptSessionsAreAddedToThePlan() async {
    let client = StreamingPlanClient()
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), tokenProvider: { "t" })
    store.goalId = "goal-1"
    store.start()
    await settled(store)

    store.toggle(0)
    let added = await store.insert()

    #expect(added == 1)
    #expect(client.inserted.first?.sessions.map(\.title) == ["Tempo vélo"])
    #expect(client.inserted.first?.goalId == "goal-1")
    #expect(!store.isReady)
}

@MainActor
@Test func aFailedInsertKeepsTheWeekOnScreen() async {
    let client = StreamingPlanClient()
    client.insertFails = true
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), tokenProvider: { "t" })
    store.start()
    await settled(store)

    #expect(await store.insert() == nil)
    #expect(store.isReady)
    #expect(store.insertError != nil)
}

@MainActor
@Test func aFailedGenerationSaysWhyAndCanStartAgain() async {
    let client = StreamingPlanClient()
    client.fails = true
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), tokenProvider: { "t" })
    store.start()
    await settled(store)

    guard case .failed = store.phase else {
        Issue.record("The generation should have failed")
        return
    }
    client.fails = false
    store.start()
    await settled(store)
    #expect(store.isReady)
}
