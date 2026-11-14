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

@MainActor
@Test func theHeroLocksTheAgeBelowProAndNeverKeepsIt() throws {
    // Even a payload that carried an age below Pro keeps none of it.
    let leaked = """
    { "biologicalAge": { "years": 31, "chronologicalYears": 35 }, "biologicalAgeAccess": "pro_required",
      "normed": 4, "inNorm": 4, "highlights": [] }
    """
    let synthesis = try JSONDecoder().decode(V1HealthSynthesis.self, from: Data(leaked.utf8))
    #expect(synthesis.biologicalAge == nil)
    #expect(SanteHero.Mode(synthesis) == .locked)

    let age = V1BiologicalAge(years: 31, chronologicalYears: 35, method: nil, confidence: nil, computedAt: nil)
    #expect(SanteHero.Mode(V1HealthSynthesis(biologicalAge: age)) == .age(age))
    #expect(SanteHero.Mode(V1HealthSynthesis(normed: 3, inNorm: 2)) == .norms)
}

@Test func stepsPastAThousandReadInThousands() {
    #expect(SanteReadout.steps(812) == "812")
    #expect(SanteReadout.steps(3_234) == "3,2 k")
    #expect(SanteReadout.steps(12_480) == "12 k")
    #expect(SanteReadout.signedDelta(3_234, for: .steps) == "+3,2 k pas")
}

@Test func theCheckUpOpensOnWhatThereIsToWatch() {
    #expect(SanteHeroReadout.headline(normed: 0, watchCount: 0) == nil)
    #expect(SanteHeroReadout.headline(normed: 4, watchCount: 0)?.text == "Rien à surveiller")
    #expect(SanteHeroReadout.headline(normed: 4, watchCount: 0)?.status == .good)
    #expect(SanteHeroReadout.headline(normed: 4, watchCount: 1)?.text == "1 point à surveiller")
    #expect(SanteHeroReadout.headline(normed: 0, watchCount: 3)?.status == .watch)
    #expect(SanteHeroReadout.wash(watchCount: 0) == .good)
    #expect(SanteHeroReadout.wash(watchCount: 2) == .watch)
}

@Test func aNeutralToneCarriesNoPill() {
    #expect(SanteHeroReadout.status(.good) == .good)
    #expect(SanteHeroReadout.status(.watch) == .watch)
    #expect(SanteHeroReadout.status(.neutral) == nil)
    #expect(SanteHeroReadout.word(.good) == "Bon")
    #expect(SanteHeroReadout.word(.watch) == "À surveiller")
}

@Test func theAgeIsReadAgainstTheCivilOneInWords() {
    func age(_ years: Double, civil: Double?) -> V1BiologicalAge {
        V1BiologicalAge(years: years, chronologicalYears: civil, method: nil, confidence: nil, computedAt: nil)
    }
    #expect(SanteHeroReadout.ageNote(age(25, civil: 25)) == "comme ton âge civil")
    #expect(SanteHeroReadout.ageNote(age(31, civil: 34)) == "3 ans de moins")
    #expect(SanteHeroReadout.ageNote(age(36, civil: 35)) == "1 an de plus")
    #expect(SanteHeroReadout.ageNote(age(31, civil: nil)) == nil)
}

@Test func aTrendIsDrawnOnItsOwnSpan() {
    let start = Date(timeIntervalSince1970: 0)
    let points = [50.0, 47, 53].enumerated().map { CorpsPoint(date: start.addingTimeInterval(Double($0.offset) * 86_400), value: $0.element) }
    #expect(SanteTrendReadout.normalised(points).map(\.value) == [0.5, 0, 1])
    #expect(SanteTrendReadout.normalised([points[0], points[0]]).map(\.value) == [0.5, 0.5])
    #expect(SanteTrendReadout.normalised([]).isEmpty)
    let marker = V1HealthMarker(key: .hrv, value: 60, series: points)
    #expect(SanteTrendReadout.drawable([marker, V1HealthMarker(key: .weight, value: 70)]) == [marker])
}

@Test func aTableRowSaysTheStatusAsAWord() {
    let good = SanteTable.Row(V1HealthMarker(key: .restingHr, value: 47, norm: V1HealthNorm(band: "b", label: "Niveau athlète", tone: .good, reference: "")))
    #expect(good.name == "FC de repos")
    #expect(good.status?.word == "Bon")
    #expect(good.value == "47 bpm")
    #expect(SanteTable.Row(V1HealthMarker(key: .weight, value: 71.4)).status == nil)
    #expect(SanteReadout.biomarkers(6) == "6 biomarqueurs")
    #expect(SanteReadout.markers(1) == "1 repère")
}
