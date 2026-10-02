import Testing
@testable import Sharpit

private func set(_ exercise: String, _ sets: Int, _ reps: Int, kg: Double? = nil, sec: Int? = nil) -> V1ActivityStrengthSet {
    V1ActivityStrengthSet(exercise: exercise, sets: sets, reps: reps, durationSec: sec, weightKg: kg)
}

@Test func exercisesKeepTheSessionOrderAndGatherTheirBlocks() {
    let exercises = StrengthExerciseReadout.exercises(from: [
        set("Squat", 3, 8, kg: 80),
        set("Gainage", 3, 0, sec: 45),
        set("Squat", 1, 5, kg: 90),
    ])

    #expect(exercises.map(\.exercise) == ["Squat", "Gainage"])
    #expect(exercises[0].lines == ["3 × 8 · 80 kg", "1 × 5 · 90 kg"])
    #expect(exercises[1].lines == ["3 × 45 s"])
}

@Test func volumeCountsOnlyLoadedSets() {
    let exercises = StrengthExerciseReadout.exercises(from: [
        set("Squat", 3, 8, kg: 80),
        set("Tractions", 4, 6),
    ])

    #expect(exercises[0].volumeKg == 1_920)
    #expect(exercises[1].volumeKg == nil)
    #expect(exercises[1].lines == ["4 × 6"])
}

@Test func loadsReadInFrenchWithOneDecimalAtMost() {
    #expect(StrengthExerciseReadout.kilograms(22.5) == "22,5 kg")
    #expect(StrengthExerciseReadout.kilograms(60) == "60 kg")
    #expect(StrengthExerciseReadout.line(set("Planche", 2, 0, sec: 120)) == "2 × 2 min")
}

@Test func blankExerciseNamesAreLeftOut() {
    #expect(StrengthExerciseReadout.exercises(from: [set("  ", 3, 8)]).isEmpty)
}
