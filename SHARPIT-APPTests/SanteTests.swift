import Foundation
import SwiftData
import Testing
@testable import Sharpit

private let overviewJSON = """
{
  "apiVersion": 1,
  "synthesis": {
    "biologicalAge": null,
    "biologicalAgeAccess": "pro_required",
    "normed": 4,
    "inNorm": 3,
    "highlights": [
      { "key": "restingHr", "delta": 5.2, "tone": "watch" },
      { "key": "someFutureMarker", "delta": 1, "tone": "good" }
    ]
  },
  "watch": [
    { "key": "restingHr", "title": "Fréquence cardiaque au repos en hausse", "detail": "+5 bpm au-dessus de ta moyenne depuis 4 jours." }
  ],
  "vitals": [
    {
      "key": "restingHr", "value": 52.4, "unit": "bpm", "basis": "average7",
      "measuredAt": "2026-09-28T06:00:00.000Z",
      "norm": { "band": "low", "label": "Basse, signe de bonne forme", "tone": "good", "reference": "AHA" },
      "trend": { "recent": 52.4, "baseline": 47.2, "delta": 5.2, "stable": false, "tone": "watch" },
      "series": [{ "date": "2026-09-27", "value": 51 }, { "date": "2026-09-28", "value": 53 }]
    },
    { "key": "someFutureMarker", "value": 1, "basis": "latest", "series": [] },
    {
      "key": "sleep", "value": 432, "unit": "min", "basis": "average7",
      "measuredAt": "2026-09-28T06:00:00.000Z", "norm": null,
      "trend": { "recent": 432, "baseline": 440, "delta": -8, "stable": true, "tone": "neutral" },
      "series": []
    }
  ],
  "body": [
    { "key": "weight", "value": 72.4, "unit": "kg", "basis": "latest", "measuredAt": "2026-09-27T07:00:00.000Z",
      "norm": null, "trend": { "recent": 72.4, "baseline": 74.2, "delta": -1.8, "stable": false, "tone": "neutral" },
      "series": [], "target": 70 }
  ],
  "daily": []
}
"""

@Test func theCheckUpDecodesAndDropsWhatItDoesNotKnow() throws {
    let overview = try JSONDecoder().decode(V1HealthOverview.self, from: Data(overviewJSON.utf8))

    #expect(overview.vitals.map(\.key) == [.restingHr, .sleep])
    #expect(overview.synthesis.highlights.map(\.key) == [.restingHr])
    #expect(overview.synthesis.biologicalAgeRequiresPro)
    #expect(overview.watch.count == 1)
    let heart = try #require(overview.marker(.restingHr))
    #expect(heart.series.count == 2)
    #expect(heart.norm?.tone == .good)
    #expect(overview.marker(.weight)?.target == 70)
}

@MainActor
@Test func markersReadInTheAthletesWords() throws {
    let overview = try JSONDecoder().decode(V1HealthOverview.self, from: Data(overviewJSON.utf8))
    let heart = try #require(overview.marker(.restingHr))
    let sleep = try #require(overview.marker(.sleep))
    let weight = try #require(overview.marker(.weight))

    #expect(SanteReadout.value(heart).text == "52")
    #expect(SanteReadout.value(heart).unit == "bpm")
    #expect(SanteReadout.value(sleep).text == "7 h 12")
    #expect(SanteReadout.value(weight).text == "72,4")
    #expect(SanteReadout.basis(heart) == "moyenne 7 jours")

    #expect(SanteReadout.trend(heart) == "+5 bpm sur le mois")
    #expect(SanteReadout.trend(sleep) == "Stable sur le mois")
    // Weight has no better direction, but a change of 1,8 kg is still named.
    #expect(SanteReadout.trend(weight) == "−1,8 kg sur le mois")

    #expect(SanteReadout.highlight(overview.synthesis.highlights[0]) == "FC de repos +5 bpm")
    #expect(SanteReadout.synthesis(overview.synthesis) == "3 repères sur 4 dans leur norme")
    #expect(SanteReadout.synthesis(V1HealthSynthesis(normed: 2, inNorm: 2)) == "Tes 2 repères sont dans leur norme")
    #expect(SanteReadout.synthesis(V1HealthSynthesis()) == nil)
    #expect(SanteReadout.comparison(heart, trend: heart.trend!) == "Tes 7 derniers jours : 52 bpm · le mois d'avant : 47 bpm")
}

@MainActor
@Test func onlyMarkersWithALongerHistoryOpenTheCorpsDrawer() {
    #expect(SanteReadout.corpsKey(.restingHr) == .restingHr)
    #expect(SanteReadout.corpsKey(.vo2max) == .vo2maxRun)
    #expect(SanteReadout.corpsKey(.sleep) == nil)
    #expect(SanteReadout.corpsKey(.steps) == nil)
}

private actor StubHealthClient: HealthOverviewServing {
    var answer: Result<Data, SharpitAPIError>

    init(_ answer: Result<Data, SharpitAPIError>) { self.answer = answer }

    func healthOverviewData(token: String) async throws -> Data { try answer.get() }

    func set(_ answer: Result<Data, SharpitAPIError>) { self.answer = answer }
}

@MainActor
@Test func santePaintsItsLastCheckUpAndKeepsItWhenARefreshFails() async throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let client = StubHealthClient(.success(Data(overviewJSON.utf8)))

    let first = SanteStore(client: client, tokenProvider: { "t" }, modelContext: context)
    #expect(first.phase == .loading)
    await first.load()
    #expect(first.phase == .loaded)

    // A new visit paints the kept answer before the network, and a refused refresh keeps it.
    await client.set(.failure(.badRequest))
    let second = SanteStore(client: client, tokenProvider: { "t" }, modelContext: context)
    #expect(second.phase == .loaded)
    await second.load()
    #expect(second.phase == .loaded)
    #expect(second.refreshFailed)
}

@MainActor
@Test func aFirstReadThatFailsSaysSo() async {
    let store = SanteStore(client: StubHealthClient(.failure(.badRequest)), tokenProvider: { "t" })
    await store.load()
    #expect(store.phase == .failed("Lecture de ta santé impossible."))
}
