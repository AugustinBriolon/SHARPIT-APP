import Foundation
import Testing
@testable import Sharpit

private actor RecordingExerciseClient: StrengthExerciseServing {
    var library: [V1StrengthExercise]
    private(set) var saved: [(name: String, note: String)] = []
    var failsOnSave = false

    init(library: [V1StrengthExercise]) { self.library = library }

    func exercises(token: String) async throws -> [V1StrengthExercise] { library }

    func saveNote(name: String, note: String, token: String) async throws {
        if failsOnSave { throw SharpitAPIError.server }
        saved.append((name, note))
    }

    func progression(name: String, token: String) async throws -> [V1ExerciseSession] { [] }

    func failNextSaves() { failsOnSave = true }
}

private func exercise(_ name: String, athleteNote: String? = nil) -> V1StrengthExercise {
    V1StrengthExercise(
        name: name, athleteNote: athleteNote,
        last: .init(date: "2026-11-10", sets: 4, reps: 8, weightKg: 60, durationSec: nil)
    )
}

@Test func anExercisesStandingNoteIsReadFromTheServer() throws {
    let json = #"{"exercises":[{"name":"Squat","athleteNote":"Talons au sol","sessions":2,"last":{"date":"2026-11-10","sets":4,"reps":8,"weightKg":80,"durationSec":null},"best":{}}]}"#
    let read = try JSONDecoder().decode(V1StrengthExercisesResponse.self, from: Data(json.utf8)).exercises
    #expect(read.first?.athleteNote == "Talons au sol")
    let older = #"{"exercises":[{"name":"Squat","sessions":1,"last":{"date":"2026-11-10","sets":4,"reps":8},"best":{}}]}"#
    #expect(try JSONDecoder().decode(V1StrengthExercisesResponse.self, from: Data(older.utf8)).exercises.first?.athleteNote == nil)
}

@MainActor
@Test func aSavedNoteShowsAtOnceUnderEverySpellingOfTheExercise() async throws {
    let client = RecordingExerciseClient(library: [exercise("Développé couché")])
    let store = StrengthLibraryStore(client: client)
    await store.load(tokenProvider: { "t" })

    try await store.saveNote(name: "developpe COUCHE", note: "  Omoplates serrées ", tokenProvider: { "t" })
    #expect(store.athleteNote(of: "Développé couché") == "Omoplates serrées")
    #expect(store.history(of: "Développé couché")?.athleteNote == "Omoplates serrées")
    #expect(await client.saved.first?.note == "Omoplates serrées")

    // A note on an exercise never logged is kept for the launch too.
    try await store.saveNote(name: "Hip thrust", note: "Banc bas", tokenProvider: { "t" })
    #expect(store.athleteNote(of: "hip thrust") == "Banc bas")

    try await store.saveNote(name: "Développé couché", note: "   ", tokenProvider: { "t" })
    #expect(store.athleteNote(of: "Développé couché") == nil)
}

@MainActor
@Test func aRefusedNoteIsNotShownAsSaved() async {
    let client = RecordingExerciseClient(library: [exercise("Squat", athleteNote: "Talons au sol")])
    let store = StrengthLibraryStore(client: client)
    await store.load(tokenProvider: { "t" })
    await client.failNextSaves()

    await #expect(throws: SharpitAPIError.self) {
        try await store.saveNote(name: "Squat", note: "Autre", tokenProvider: { "t" })
    }
    #expect(store.athleteNote(of: "Squat") == "Talons au sol")
}

@Test func thePickerShowsTheAthletesNoteUnderTheHistory() {
    #expect(ExercisePickerReadout.detail(exercise("Squat", athleteNote: "Talons au sol")) == "Dernière fois 4 × 8 · 60 kg\nTalons au sol")
    #expect(ExercisePickerReadout.detail(exercise("Squat")) == "Dernière fois 4 × 8 · 60 kg")
}
