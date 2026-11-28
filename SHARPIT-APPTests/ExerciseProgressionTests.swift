import Foundation
import Testing
@testable import Sharpit

private func session(_ date: String, kg: Double? = nil, hold: Int? = nil) -> V1ExerciseSession {
    V1ExerciseSession(
        date: date,
        blocks: [.init(sets: 3, reps: hold == nil ? 8 : 1, weightKg: kg, durationSec: hold)],
        bestWeightKg: kg,
        bestDurationSec: hold,
        volumeKg: (kg ?? 0) * 24
    )
}

@Test func progressionDecodesTheServersDays() throws {
    let json = #"{"apiVersion":1,"sessions":[{"date":"2026-11-08","blocks":[{"sets":3,"reps":8,"weightKg":60,"durationSec":null}],"bestWeightKg":60,"bestDurationSec":null,"volumeKg":1440}]}"#
    let sessions = try JSONDecoder().decode(V1ExerciseProgressionResponse.self, from: Data(json.utf8)).sessions
    #expect(sessions.first?.bestWeightKg == 60)
    #expect(ExerciseProgressionReadout.lines(sessions[0]) == ["3 × 8 · 60 kg"])
}

@Test func aLoadedExerciseIsDrawnByItsEstimatedMaxAndSkipsUnloadedDays() {
    let points = ExerciseProgressionReadout.points([
        session("2026-10-01", kg: 55), session("2026-10-15"), session("2026-11-08", kg: 65),
    ])
    // 3 × 8: load × (1 + 8 / 30).
    #expect(points.map { $0.value.rounded() } == [70, 82])
    #expect(points.allSatisfy { $0.measure == .estimatedMax })
    let change = ExerciseProgressionReadout.change(points)
    #expect(change?.hasPrefix("70 kg → 82 kg depuis le ") == true)
}

@Test func heavierAndFewerReadsBelowLighterAndMoreWhenItWasWeaker() {
    let heavy = V1ExerciseSession(
        date: "2026-11-01", blocks: [.init(sets: 3, reps: 3, weightKg: 80, durationSec: nil)],
        bestWeightKg: 80, bestDurationSec: nil, volumeKg: 720
    )
    let lighter = V1ExerciseSession(
        date: "2026-11-08", blocks: [.init(sets: 3, reps: 12, weightKg: 70, durationSec: nil)],
        bestWeightKg: 70, bestDurationSec: nil, volumeKg: 2520
    )
    let points = ExerciseProgressionReadout.points([heavy, lighter])
    // 80 × 1,1 = 88 against 70 × 1,4 = 98: the lighter day was the stronger one.
    #expect(points.map { $0.value.rounded() } == [88, 98])
    #expect(ExerciseProgressionReadout.estimatedMax(kg: 100, reps: 1) == 100)
}

@Test func anExerciseNeverLoadedIsDrawnByItsBestSet() {
    let points = ExerciseProgressionReadout.points([session("2026-10-01"), session("2026-11-08")])
    #expect(points.map(\.value) == [8, 8])
    #expect(points.first?.measure == .reps)
    #expect(ExerciseProgressionReadout.figure(points[0]) == "8 rép.")
}

@Test func aHeldExerciseIsDrawnByItsLongestHold() {
    let points = ExerciseProgressionReadout.points([session("2026-10-01", hold: 45), session("2026-11-08", hold: 90)])
    #expect(points.map(\.value) == [45, 90])
    #expect(ExerciseProgressionReadout.figure(points[1]) == "1 min 30 s")
}

@Test func oneDayHasNothingToCompare() {
    #expect(ExerciseProgressionReadout.change(ExerciseProgressionReadout.points([session("2026-11-08", kg: 60)])) == nil)
}
