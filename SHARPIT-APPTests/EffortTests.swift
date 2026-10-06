import Foundation
import Testing
@testable import Sharpit

/// `projectV1Effort`'s output for a loaded day, as `effort.test.ts` builds it.
let effortJSON = """
{
  "apiVersion": 1, "trainingDayId": "2026-10-04", "empty": null,
  "strain": { "score": 12.4, "label": "Charge élevée", "subtitle": "Séance intense ce matin", "tone": "elevated" },
  "verdict": { "key": "MAINTAIN", "label": "Maintenir", "tone": "good" },
  "fatigueTypeLabel": "Charge dominante", "trainingCapacity": "REDUCED",
  "rationale": ["Charge aiguë au-dessus de la chronique"],
  "keyEvidence": ["Trois jours consécutifs de charge"],
  "consecutiveDays": 3, "estimatedDaysToFresh": 2,
  "load": { "daily": 84, "weekly": 420, "acwr": 1.21, "chronicWeeklyAvg": 380, "tsb": -14, "avgWeeklyTss": 305 },
  "dimensions": [
    { "key": "load", "label": "Charge d'entraînement", "description": "Charge, montée de charge, tendance", "available": true, "score": 62, "intensity": "Élevée" },
    { "key": "neuromuscular", "label": "Neuromusculaire", "description": "Force, vitesse, récupération musculaire", "available": false, "score": null, "intensity": null },
    { "key": "metabolic", "label": "Métabolique", "description": "Volume intensité, dette lactique", "available": true, "score": 10, "intensity": "Faible" },
    { "key": "cumulative", "label": "Cumulative", "description": "Accumulation multi-semaines", "available": false, "score": null, "intensity": null },
    { "key": "psychological", "label": "Psychologique", "description": "Stress, motivation, charge mentale", "available": false, "score": null, "intensity": null }
  ],
  "dominantDimension": "load", "limitingFactor": "Charge",
  "overreaching": { "label": "Risque modéré", "tone": "caution" },
  "composition": {
    "available": true, "dominantKey": "training",
    "contributors": [
      { "key": "training", "label": "Entraînement", "description": "Activités du jour", "available": true, "load": 84, "score": 11.2, "signalSummary": null },
      { "key": "movement", "label": "Mouvement", "description": "Pas quotidiens non disponibles", "available": false, "load": null, "score": null, "signalSummary": null }
    ],
    "signals": { "steps": 8400, "stress": 31, "bodyBattery": 55 }
  },
  "pmc": [
    { "date": "2026-10-03", "ctl": 50, "atl": 60, "tsb": -10 },
    { "date": "2026-10-04", "ctl": 51, "atl": 64, "tsb": -13 }
  ],
  "weeklyTss": [{ "label": "S-1", "tss": 400 }, { "label": "Cette sem.", "tss": 210 }],
  "confidencePct": 74, "completenessLabel": "Partielles"
}
"""

private func decodedEffort(_ json: String = effortJSON) throws -> V1EffortResponse {
    try JSONDecoder().decode(V1EffortResponse.self, from: Data(json.utf8))
}

@Test func effortDecodesTheV1Contract() throws {
    let effort = try decodedEffort()
    #expect(effort.strain.score == 12.4)
    #expect(effort.strain.tone == .elevated)
    #expect(effort.verdict.tone == .good)
    #expect(effort.dimensions.map(\.key) == ["load", "neuromuscular", "metabolic", "cumulative", "psychological"])
    #expect(effort.dimensions[1].available == false)
    #expect(effort.dimensions[1].score == nil)
    #expect(effort.load.tsb == -14)
    #expect(effort.overreaching?.tone == .caution)
    #expect(effort.composition.signals.steps == 8400)
    #expect(effort.pmc.last?.date == "2026-10-04")
    #expect(effort.weeklyTss.last?.label == "Cette sem.")
    #expect(effort.empty == nil)
}

@Test func anEmptyEffortDayDecodesWithoutConfidence() throws {
    let json = effortJSON
        .replacingOccurrences(of: "\"empty\": null", with: "\"empty\": { \"title\": \"Pas encore de charge\", \"message\": \"Synchronise une séance.\" }")
        .replacingOccurrences(of: "\"confidencePct\": 74", with: "\"confidencePct\": null")
    let effort = try decodedEffort(json)
    #expect(effort.empty?.title == "Pas encore de charge")
    #expect(effort.confidencePct == nil)
}

@Test func theStrainReadsToTheTenth() {
    #expect(EffortReadout.strain(12.4) == "12,4")
    #expect(EffortReadout.strain(nil) == "—")
}

@Test func theLoadIsNamedForTheReading() {
    #expect(EffortReadout.dailyCaption(isExpert: false) == "Charge du jour")
    #expect(EffortReadout.dailyCaption(isExpert: true) == "TSS du jour")
    #expect(EffortReadout.rampCaption(isExpert: false) == "Montée")
    #expect(EffortReadout.rampCaption(isExpert: true) == "ACWR")
    #expect(EffortReadout.formCaption(isExpert: true) == "TSB")
}

@Test func theRampUsesTheWebsZones() {
    #expect(EffortReadout.ramp(1.21) == "1,21")
    #expect(EffortReadout.ramp(0) == "—")
    #expect(EffortReadout.rampZone(1.21) == "Zone optimale")
    #expect(EffortReadout.rampZone(0.7) == "Sous-charge")
    #expect(EffortReadout.rampZone(1.4) == "Alerte")
    #expect(EffortReadout.rampZone(1.8) == "Danger")
    #expect(EffortReadout.rampZone(0) == nil)
}

@Test func theHeroLineSaysWhenTheAthleteIsFreshFirst() throws {
    let effort = try decodedEffort()
    #expect(EffortReadout.actionLine(effort) == "Frais dans 2 jours")
    let stacked = try decodedEffort(effortJSON.replacingOccurrences(of: "\"estimatedDaysToFresh\": 2", with: "\"estimatedDaysToFresh\": null"))
    #expect(EffortReadout.actionLine(stacked) == "3 j d'accumulation")
}

@Test func aFatigueDimensionReadsHigherAsWorse() throws {
    let effort = try decodedEffort()
    #expect(EffortReadout.dimensionTone(effort.dimensions[2]) == SharpitColor.primary)
    #expect(EffortReadout.dimensionTone(effort.dimensions[1]) == SharpitColor.signalNeutral)
    #expect(EffortReadout.capacity("REDUCED") == "Capacité réduite")
}

@Test func theEffortTileReadsTheStrainAndTheVerdict() throws {
    let tile = PlanTrajectoryTile.effort(try decodedEffort())
    #expect(tile.value == "12,4")
    #expect(tile.unit == "/21")
    #expect(tile.headline == "Charge élevée")
    #expect(tile.caption == "Maintenir")
    #expect(PlanTrajectoryTile.effort(nil).value == "—")
}

private struct StubEffort: EffortServing {
    let payload: V1EffortResponse
    func effort(trainingDayId: String, token: String) async throws -> V1EffortResponse { payload }
}

@MainActor
@Test func anEffortDayLoadsThroughTheSharedStore() async throws {
    let client = StubEffort(payload: try decodedEffort())
    let store = DayResourceStore<V1EffortResponse>(failureMessage: "failed", tokenProvider: { "t" }) {
        try await client.effort(trainingDayId: $0, token: $1)
    }
    await store.load()
    guard case .loaded(let effort) = store.phase else {
        Issue.record("expected a loaded day")
        return
    }
    #expect(effort.limitingFactor == "Charge")
}
