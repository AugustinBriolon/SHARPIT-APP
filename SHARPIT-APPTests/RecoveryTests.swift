import Foundation
import Testing
@testable import Sharpit

let recoveryJSON = """
{
  "apiVersion": 1, "trainingDayId": "2026-09-21", "empty": null,
  "readinessScore": 71, "signal": { "label": "Bonne", "tone": "good" },
  "isCalibrating": false, "limiter": "Qualité du sommeil", "estimatedRecoveryDays": 1,
  "intensity": "Modérée", "rationale": ["VFC dans ta norme", "Sommeil sous la cible"],
  "dimensions": [
    { "key": "autonomic", "score": 78, "status": "NORMAL" },
    { "key": "sleep", "score": 52.5, "status": "INSUFFICIENT" },
    { "key": "loadContext", "score": 70, "status": "OPTIMAL" }
  ],
  "pillars": [
    { "key": "autonomic", "label": "Équilibre normal", "tone": "good" },
    { "key": "wellness", "label": "Bien-être faible", "tone": "caution" },
    { "key": "load", "label": "Charge optimale", "tone": "strong" }
  ],
  "dissonanceDetected": false,
  "today": { "hrv": 58, "restingHr": 49, "bodyBattery": 72, "hrvBaselineLow": 55, "hrvBaselineHigh": 70 },
  "history": [
    { "date": "2026-09-19", "hrv": 64, "restingHr": 47 },
    { "date": "2026-09-20", "hrv": 61, "restingHr": 48 },
    { "date": "2026-09-21", "hrv": 58, "restingHr": 49 }
  ],
  "alerts": [{ "key": "overreaching", "label": "Risque modéré", "tone": "caution" }],
  "keyEvidence": ["Sommeil sous la cible deux nuits de suite"],
  "confidencePct": 68, "completenessLabel": "Partielles"
}
"""

private func decodedRecovery(_ json: String = recoveryJSON) throws -> V1RecoveryResponse {
    try JSONDecoder().decode(V1RecoveryResponse.self, from: Data(json.utf8))
}

@Test func recoveryDecodesTheV1Contract() throws {
    let recovery = try decodedRecovery()
    #expect(recovery.readinessScore == 71)
    #expect(recovery.signal.tone == .good)
    #expect(recovery.dimensions.map(\.key) == ["autonomic", "sleep", "loadContext"])
    #expect(recovery.alerts.first?.tone == .caution)
}

@Test func anUnknownSignalToneReadsAsNeutral() throws {
    let recovery = try decodedRecovery(recoveryJSON.replacingOccurrences(
        of: "\"label\": \"Bonne\", \"tone\": \"good\"",
        with: "\"label\": \"Bonne\", \"tone\": \"glow\""
    ))
    #expect(recovery.signal.tone == .neutral)
}

@Test func hrvIsPlacedAgainstTheAthletesOwnNormal() {
    let within = V1RecoveryToday(hrv: 58, restingHr: nil, bodyBattery: nil, hrvBaselineLow: 55, hrvBaselineHigh: 70)
    let below = V1RecoveryToday(hrv: 50, restingHr: nil, bodyBattery: nil, hrvBaselineLow: 55, hrvBaselineHigh: 70)
    let noBaseline = V1RecoveryToday(hrv: 50, restingHr: nil, bodyBattery: nil, hrvBaselineLow: nil, hrvBaselineHigh: nil)
    #expect(RecoveryReadout.hrvPosition(within) == .within)
    #expect(RecoveryReadout.hrvPosition(below) == .below)
    #expect(RecoveryReadout.hrvPosition(noBaseline) == .unknown)
    #expect(RecoveryReadout.hrvNote(below) == "sous ta norme 55–70")
    #expect(RecoveryReadout.hrvNote(noBaseline) == nil)
}

@Test func dimensionScoresUseTheWebsBands() {
    #expect(RecoveryReadout.scoreTone(78) == SharpitColor.primary)
    #expect(RecoveryReadout.scoreTone(52.5) == SharpitColor.signalCaution)
    #expect(RecoveryReadout.scoreTone(30) == SharpitColor.signalRisk)
}

@Test func theRecoveryHorizonReadsInDays() {
    #expect(RecoveryReadout.recoveryHorizon(1) == "Récupération complète d'ici 1 jour")
    #expect(RecoveryReadout.recoveryHorizon(2.2) == "Récupération complète d'ici 3 jours")
    #expect(RecoveryReadout.recoveryHorizon(nil) == nil)
}

private struct StubRecovery: RecoveryServing {
    let payload: V1RecoveryResponse
    func recovery(trainingDayId: String, token: String) async throws -> V1RecoveryResponse { payload }
}

@MainActor
@Test func aRecoveryDayLoadsThroughTheSharedStore() async throws {
    let client = StubRecovery(payload: try decodedRecovery())
    let store = DayResourceStore<V1RecoveryResponse>(failureMessage: "failed", tokenProvider: { "t" }) {
        try await client.recovery(trainingDayId: $0, token: $1)
    }
    await store.load()
    guard case .loaded(let recovery) = store.phase else {
        Issue.record("expected a loaded day")
        return
    }
    #expect(recovery.limiter == "Qualité du sommeil")
}
