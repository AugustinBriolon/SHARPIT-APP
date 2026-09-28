import Foundation
import Testing
@testable import Sharpit

@MainActor
private final class AdjustmentClient: PlanAdjustmentServing {
    var result = V1AdaptPlanResult(summary: "Semaine allégée", changes: [
        V1AdaptChange(action: .modify, sessionId: "s1", title: "Seuil", reason: "Fatigue."),
        V1AdaptChange(action: .remove, sessionId: "s2", title: "VMA", reason: "Trop tôt."),
    ])
    var fails = false
    var applyFails = false
    private(set) var applied: [[V1AdaptChange]] = []
    private(set) var focus: String?

    func adaptPlan(days _: Int, focus: String?, token _: String, onReasoning _: @escaping @Sendable (String) -> Void) async throws -> V1AdaptPlanResult {
        self.focus = focus
        if fails { throw CoachPlanError.custom("Le coach n'a pas pu terminer.") }
        return result
    }

    func applyAdjustments(_ changes: [V1AdaptChange], token _: String) async throws {
        if applyFails { throw SharpitAPIError.server }
        applied.append(changes)
    }
}

@MainActor
@Test func theCoachProposesAndEveryChangeStartsKept() async {
    let client = AdjustmentClient()
    let store = PlanAdjustmentStore(client: client, tokenProvider: { "t" })
    store.focus = "  grosse fatigue  "

    await store.start()

    #expect(client.focus == "grosse fatigue")
    #expect(store.phase == .ready(client.result, selected: [0, 1]))
}

@MainActor
@Test func onlyTheKeptChangesAreApplied() async {
    let client = AdjustmentClient()
    let store = PlanAdjustmentStore(client: client, tokenProvider: { "t" })
    await store.start()

    store.toggle(1)
    let applied = await store.apply()

    #expect(applied == 1)
    #expect(client.applied.first?.map(\.sessionId) == ["s1"])
    #expect(store.phase == .idle)
}

@MainActor
@Test func aFailedApplyKeepsTheChangesOnScreen() async {
    let client = AdjustmentClient()
    client.applyFails = true
    let store = PlanAdjustmentStore(client: client, tokenProvider: { "t" })
    await store.start()

    #expect(await store.apply() == nil)
    #expect(store.applyError != nil)
    guard case .ready = store.phase else {
        Issue.record("The changes should stay on screen")
        return
    }
}

@MainActor
@Test func aFailedAnalysisSaysWhy() async {
    let client = AdjustmentClient()
    client.fails = true
    let store = PlanAdjustmentStore(client: client, tokenProvider: { "t" })

    await store.start()

    #expect(store.phase == .failed("Le coach n'a pas pu terminer."))
}

/// A change goes back as the server sent it, so the coach's steps are applied with it.
@Test func aChangeIsAppliedWithTheStepsTheCoachWrote() throws {
    let json = Data(#"""
    { "action": "ADD", "sessionId": null, "date": "2026-10-01", "type": "RUN", "intensity": "RECOVERY",
      "title": "Footing", "description": null, "durationMin": 30, "load": 20, "reason": "Relancer.",
      "decisionId": "d1",
      "endurancePrescription": { "blocks": [ { "steps": [ { "kind": "interval", "minutes": 30 } ] } ] } }
    """#.utf8)

    let change = try JSONDecoder().decode(V1AdaptChange.self, from: json)

    #expect(change.applyBody["endurancePrescription"]?["blocks"] != nil)
    #expect(change.applyBody["decisionId"]?.string == "d1")
}
