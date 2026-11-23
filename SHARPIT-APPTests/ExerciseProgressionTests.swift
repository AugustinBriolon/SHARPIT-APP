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

@Test func aLoadedExerciseIsDrawnByItsBestLoadAndSkipsUnloadedDays() {
    let points = ExerciseProgressionReadout.points([
        session("2026-10-01", kg: 55), session("2026-10-15"), session("2026-11-08", kg: 65),
    ])
    #expect(points.map(\.value) == [55, 65])
    #expect(points.allSatisfy { !$0.isHold })
    let change = ExerciseProgressionReadout.change(points)
    #expect(change?.hasPrefix("55 kg → 65 kg depuis le ") == true)
}

@Test func aHeldExerciseIsDrawnByItsLongestHold() {
    let points = ExerciseProgressionReadout.points([session("2026-10-01", hold: 45), session("2026-11-08", hold: 90)])
    #expect(points.map(\.value) == [45, 90])
    #expect(ExerciseProgressionReadout.figure(points[1]) == "1 min 30 s")
}

@Test func oneDayHasNothingToCompare() {
    #expect(ExerciseProgressionReadout.change(ExerciseProgressionReadout.points([session("2026-11-08", kg: 60)])) == nil)
}
