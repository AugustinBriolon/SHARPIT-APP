import Foundation
import Testing
@testable import Sharpit

@MainActor
private final class StreamingPlanClient: CoachPlanServing, PlanJobServing {
    private(set) var inserted: [(sessions: [V1GeneratedSession], goalId: String?)] = []
    var fails = false
    var insertFails = false
    var gate: V1PlanGate?

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
        return V1GeneratedPlan(summary: "Semaine", sessions: Self.week, gate: gate)
    }

    func adaptPlan(days _: Int, focus _: String?, token _: String, onReasoning _: @escaping @Sendable (String) -> Void) async throws -> V1AdaptPlanResult {
        V1AdaptPlanResult(summary: "", changes: [])
    }

    private(set) var started = 0
    var latest: V1PlanJob?

    nonisolated func startWeekJob(days _: Int, goalId _: String?, focus _: String?, startDate _: Date?, token _: String) async throws -> V1PlanJob {
        await MainActor.run { started += 1 }
        return V1PlanJob(id: "job-\(await MainActor.run { started })", status: "running")
    }

    nonisolated func planJob(id: String, token _: String) async throws -> V1PlanJob? {
        await MainActor.run {
            if fails { return V1PlanJob(id: id, status: "failed", error: "Le coach a renvoyé une proposition incomplète.") }
            return V1PlanJob(id: id, status: "ready", plan: V1GeneratedPlan(summary: "Semaine", sessions: Self.week, gate: gate))
        }
    }

    nonisolated func latestPlanJob(token _: String) async throws -> V1PlanJob? {
        await MainActor.run { latest }
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

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "PlanGeneration-\(UUID().uuidString)")!
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
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), defaults: freshDefaults(), pollInterval: .milliseconds(1), tokenProvider: { "t" })

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
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), defaults: freshDefaults(), pollInterval: .milliseconds(1), tokenProvider: { "t" })
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
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), defaults: freshDefaults(), pollInterval: .milliseconds(1), tokenProvider: { "t" })
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
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), defaults: freshDefaults(), pollInterval: .milliseconds(1), tokenProvider: { "t" })
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

/// A session the server's safety check rejected would be refused (422) and fail the whole
/// week: it is never kept, and cannot be ticked back.
@MainActor
@Test func aSessionTheGateRejectedIsNeverKept() async {
    let client = StreamingPlanClient()
    client.gate = V1PlanGate(sessions: [
        V1GateVerdict(status: "ACCEPTED"),
        V1GateVerdict(status: "REJECTED", findings: [.init(severity: "REJECTED", rationale: "Zone sensible : genou.")]),
    ])
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), defaults: freshDefaults(), pollInterval: .milliseconds(1), tokenProvider: { "t" })
    store.start()
    await settled(store)

    store.toggle(1)
    guard case .ready(let plan, let selected) = store.phase else {
        Issue.record("The week should be ready")
        return
    }
    #expect(selected == [0])
    #expect(plan.verdict(at: 1)?.reason == "Zone sensible : genou.")

    _ = await store.insert()
    #expect(client.inserted.first?.sessions.map(\.title) == ["Footing"])
}

@Test func theGateVerdictDecodesFromThePlan() throws {
    let json = Data(#"""
    { "summary": "S", "sessions": [], "gate": { "sessions": [
        { "status": "WARNING", "findings": [ { "ruleCode": "load", "severity": "WARNING", "rationale": "Charge élevée.", "evidenceRefs": [] } ],
          "requiredAssumptions": [], "saferAlternative": null, "proposal": {} } ], "planLevelFindings": [] } }
    """#.utf8)

    let plan = try JSONDecoder().decode(V1GeneratedPlan.self, from: json)

    #expect(plan.gate?.sessions.first?.status == "WARNING")
    #expect(plan.gate?.sessions.first?.reason == "Charge élevée.")
}

/// A week finished while the app was closed is shown on the return, once.
@MainActor
@Test func aWeekFinishedWhileAwayIsPickedUpOnce() async {
    let client = StreamingPlanClient()
    client.latest = V1PlanJob(id: "job-away", status: "ready", plan: V1GeneratedPlan(summary: "S", sessions: StreamingPlanClient.week))
    let defaults = freshDefaults()
    let store = PlanGenerationStore(plan: client, goalClient: NoGoals(), defaults: defaults, pollInterval: .milliseconds(1), tokenProvider: { "t" })

    await store.resume()
    #expect(store.isReady)

    _ = await store.insert()
    let again = PlanGenerationStore(plan: client, goalClient: NoGoals(), defaults: defaults, pollInterval: .milliseconds(1), tokenProvider: { "t" })
    await again.resume()
    #expect(!again.isReady)
}

/// A proposal opens on the steps the server resolved, and says why the coach wrote it.
@Test func aProposedSessionOpensOnItsBreakdownAndItsReason() throws {
    let json = Data(#"""
    { "dayOffset": 1, "date": "2026-09-29", "type": "RUN", "intensity": "THRESHOLD", "title": "Seuil",
      "description": "3 × 8 min au seuil", "durationMin": 55, "load": 62, "rationale": "Progression vers le M.",
      "breakdown": { "steps": [ { "key": "0-0", "label": "Échauffement", "detail": "15 min", "target": null, "repeat": 1, "notes": null } ],
                     "derived": false, "warnings": [] } }
    """#.utf8)

    let session = try JSONDecoder().decode(V1GeneratedSession.self, from: json)
    let preview = PlannedSessionPreview(generated: session)

    #expect(session.breakdown?.steps.map(\.label) == ["Échauffement"])
    #expect(preview.sessionId == nil)
    #expect(preview.steps.count == 1)
    #expect(preview.rationale == "Progression vers le M.")
    // The steps are the instruction: no prose « Consigne » beside them.
    #expect(preview.notes == nil)
    #expect(preview.metrics.map(\.value) == ["55 min", "Seuil", "62"])
}

@Test func aProposalWithoutBreakdownStillDecodes() throws {
    let json = Data(#"{ "date": "2026-09-29", "type": "SWIM", "title": "Nage facile", "breakdown": "oops" }"#.utf8)
    let session = try JSONDecoder().decode(V1GeneratedSession.self, from: json)
    #expect(session.breakdown == nil)
    #expect(PlannedSessionPreview(generated: session).steps.isEmpty)
}

/// The wait names what the coach reads, one line after another, before any session is written.
@Test func theWaitNamesWhatTheCoachReads() {
    #expect(GeneratingWeekView.readingSteps.first == "Analyse de ton profil")
    #expect(GeneratingWeekView.readingSteps.count >= 3)
}
