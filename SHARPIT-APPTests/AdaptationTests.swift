import Foundation
import Testing
@testable import Sharpit

/// `projectV1Adaptation`'s output for a loaded day, as `adaptation.test.ts` builds it.
let adaptationJSON = """
{
  "apiVersion": 1, "trainingDayId": "2026-10-04", "empty": null,
  "index": 64, "status": { "label": "Consolidation", "tone": "good" },
  "trendLabel": "En progression",
  "verdict": { "key": "CONSOLIDATE", "label": "Consolider", "tone": "good" },
  "loadMultiplier": 1,
  "rationale": ["La VFC suit la charge"],
  "keyEvidence": ["Allure en hausse à FC égale"],
  "limitingFactor": "Qualité de récupération",
  "plateauRisk": false, "overreachingWithoutAdaptation": true,
  "dimensions": [
    { "key": "loadProgression", "label": "Progression de charge", "description": "La charge évolue-t-elle ?", "available": true, "score": 70, "isLimiting": false },
    { "key": "recoveryQuality", "label": "Qualité de récupération", "description": "La récupération soutient-elle ?", "available": true, "score": 41, "isLimiting": true },
    { "key": "neuromuscularEfficiency", "label": "Efficacité neuromusculaire", "description": "Dérive FC", "available": false, "score": null, "isLimiting": false }
  ],
  "historyLength": 42, "confidencePct": 61
}
"""

private func decodedAdaptation(_ json: String = adaptationJSON) throws -> V1AdaptationResponse {
    try JSONDecoder().decode(V1AdaptationResponse.self, from: Data(json.utf8))
}

@Test func adaptationDecodesTheV1Contract() throws {
    let adaptation = try decodedAdaptation()
    #expect(adaptation.index == 64)
    #expect(adaptation.status.tone == .good)
    #expect(adaptation.verdict.key == "CONSOLIDATE")
    #expect(adaptation.overreachingWithoutAdaptation)
    #expect(adaptation.dimensions.first { $0.isLimiting }?.key == "recoveryQuality")
    #expect(adaptation.dimensions[2].score == nil)
    #expect(adaptation.historyLength == 42)
}

@Test func theBrakeComesFirstAndAMissingNeuromuscularIsExplained() throws {
    let adaptation = try decodedAdaptation()
    #expect(AdaptationReadout.displayedDimensions(adaptation).map(\.key) == ["recoveryQuality", "loadProgression"])
    #expect(AdaptationReadout.isNeuromuscularMissing(adaptation))
    #expect(AdaptationReadout.limitingScore(adaptation) == 41)
}

@Test func theLoadMultiplierReadsAsTheWebsMarker() {
    #expect(AdaptationReadout.loadMultiplier(1) == "Neutre")
    #expect(AdaptationReadout.loadMultiplier(0.9) == "×0,90")
    #expect(AdaptationReadout.loadMultiplierNote(0.9) == "Volume réduit pour laisser l'adaptation rattraper")
}

@Test func aMissingTrendIsNotShown() {
    #expect(AdaptationReadout.trend("—") == nil)
    #expect(AdaptationReadout.trend("En progression") == "En progression")
    #expect(AdaptationReadout.history(42) == "42 jours d'historique")
}

@Test func theAdaptationTileReadsTheIndexAndTheTrend() throws {
    let tile = PlanTrajectoryTile.adaptation(try decodedAdaptation())
    #expect(tile.value == "64")
    #expect(tile.headline == "Consolidation")
    #expect(tile.caption == "En progression")
}

private struct StubAdaptation: AdaptationServing {
    let payload: V1AdaptationResponse
    func adaptation(trainingDayId: String, token: String) async throws -> V1AdaptationResponse { payload }
}

@MainActor
@Test func anEmptyAdaptationDayShowsItsEmptyState() async throws {
    let json = adaptationJSON
        .replacingOccurrences(of: "\"empty\": null", with: "\"empty\": { \"title\": \"Adaptation en cours de consolidation\", \"message\": null }")
    let client = StubAdaptation(payload: try decodedAdaptation(json))
    let store = DayResourceStore<V1AdaptationResponse>(failureMessage: "failed", tokenProvider: { "t" }) {
        try await client.adaptation(trainingDayId: $0, token: $1)
    }
    await store.load()
    guard case .empty(let empty) = store.phase else {
        Issue.record("expected an empty day")
        return
    }
    #expect(empty.title == "Adaptation en cours de consolidation")
}
