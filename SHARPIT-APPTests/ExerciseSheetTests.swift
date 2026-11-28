import Foundation
import Testing
@testable import Sharpit

/// Answers each spelling with the days logged under it, as the server folds names.
private actor SpellingProgressionClient: StrengthExerciseServing {
    let library: [V1StrengthExercise]
    let days: [String: [V1ExerciseSession]]
    private(set) var asked: [String] = []

    init(library: [V1StrengthExercise], days: [String: [V1ExerciseSession]]) {
        self.library = library
        self.days = days
    }

    func exercises(token: String) async throws -> [V1StrengthExercise] { library }
    func saveNote(name: String, note: String, token: String) async throws {}

    func progression(name: String, token: String) async throws -> [V1ExerciseSession] {
        asked.append(name)
        return days[name] ?? []
    }
}

private func logged(_ name: String) -> V1StrengthExercise {
    V1StrengthExercise(name: name, last: .init(date: "2026-11-10", sets: 3, reps: 8, weightKg: 20, durationSec: nil))
}

private func day(_ date: String, kg: Double) -> V1ExerciseSession {
    V1ExerciseSession(
        date: date,
        blocks: [.init(sets: 3, reps: 8, weightKg: kg, durationSec: nil)],
        bestWeightKg: kg, bestDurationSec: nil, volumeKg: 24 * kg
    )
}

@Test func theProgressionReadsEverySpellingTheHistoryGathers() async throws {
    // « Traction (lestée) » is one exercise here and two on the server, which keeps punctuation.
    let client = SpellingProgressionClient(
        library: [logged("Traction lestée"), logged("Traction (lestée)"), logged("Squat")],
        days: [
            "Traction (lestée)": [day("2026-11-03", kg: 10)],
            "Traction lestée": [day("2026-11-10", kg: 12.5)],
        ]
    )
    let store = StrengthLibraryStore(client: client)
    await store.load(tokenProvider: { "t" })

    let sessions = try await store.progression(of: "Traction (lestée)", tokenProvider: { "t" })

    #expect(sessions.map(\.date) == ["2026-11-03", "2026-11-10"])
    #expect(await client.asked == ["Traction (lestée)", "Traction lestée"])
}

@Test func aSpellingTheServerFoldsTheSameIsAskedOnce() {
    let library = [logged("Développé couché"), logged("developpe  couche")]
    #expect(StrengthProgressionMerge.spellings(of: "Développé couché", in: library) == ["Développé couché"])
}

@Test func twoSpellingsDoneTheSameDayAreOneDay() {
    let merged = StrengthProgressionMerge.merged([day("2026-11-10", kg: 10), day("2026-11-10", kg: 15), day("2026-11-01", kg: 5)])
    #expect(merged.map(\.date) == ["2026-11-01", "2026-11-10"])
    #expect(merged[1].blocks.count == 2)
    #expect(merged[1].bestWeightKg == 15)
    #expect(merged[1].volumeKg == 24 * 25)
}

@Test func theCoachsFrenchNamesFindTheirPicture() {
    // None of these is an alias: they were drawn without a picture.
    #expect(ExerciseMediaCatalog.resolveCatalogId(name: "Abdos jackknife") == "0507")
    #expect(ExerciseMediaCatalog.resolveCatalogId(name: "Pont fessier") != nil)
    #expect(ExerciseMediaCatalog.resolveCatalogId(name: "Élévations latérales") != nil)
    #expect(ExerciseMediaCatalog.gifURL(name: "Gainage planche (poids du corps)") != nil)
    // A name that shares too little with any of the catalog's stays without one.
    #expect(ExerciseMediaCatalog.resolveCatalogId(name: "Respiration diaphragmatique") == nil)
}

@Test func aListOfExercisesNamesTheSetsWithoutTheLoad() {
    #expect(StrengthHistoryReadout.lastSets(logged("Squat")) == "Dernière fois 3 × 8")
    #expect(StrengthHistoryReadout.lastFigure(logged("Squat")) == "3 × 8 · 20 kg")
}

@Test func anExerciseCardSaysWhereItsSetsStand() {
    #expect(GuidedStrengthReadout.setsLine(done: 0, total: 3) == "3 séries")
    #expect(GuidedStrengthReadout.setsLine(done: 1, total: 3) == "1 sur 3 séries")
    #expect(GuidedStrengthReadout.setsLine(done: 3, total: 3) == "3 séries faites")
    #expect(GuidedStrengthReadout.setsLine(done: 0, total: 1) == "1 série")
}

@Test func theSheetSearchesTheTechniqueOnYouTube() throws {
    let url = try #require(ExerciseGuideReadout.youTubeSearchURL("Abdos jackknife"))
    #expect(url.host() == "www.youtube.com")
    #expect(url.absoluteString.contains("search_query=Abdos%20jackknife%20technique"))
}
