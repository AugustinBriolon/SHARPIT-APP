import Foundation
import Testing
@testable import Sharpit

/// The athlete's remarks of 2026-11-15: the compliance score among the figures, the routines as
/// one line, a day's second session, a trend read under the finger.
struct FeedbackPassTests {
    @Test func theComplianceScoreIsAFigureThatOpensItsReading() throws {
        let analysis = try JSONDecoder().decode(V1PlannedSessionAnalysis.self, from: Data(#"{"complianceScore": 85.6}"#.utf8))
        var opened = false
        let figures = ActivityHeroMetricData.compliance(analysis) { opened = true }
        #expect(figures.map(\.value) == ["86"])
        #expect(figures.first?.unit == "/ 100")
        figures.first?.action?()
        #expect(opened)

        let unscored = try JSONDecoder().decode(V1PlannedSessionAnalysis.self, from: Data("{}".utf8))
        #expect(ActivityHeroMetricData.compliance(unscored) {}.isEmpty)
        #expect(ActivityHeroMetricData.compliance(nil) {}.isEmpty)
    }

    @Test func routinesReadAsOneLine() {
        let move = V1RoutineMove(name: "Fente basse", dose: "30 s", cue: nil)
        let both = V1SessionRoutines(
            warmup: V1SessionRoutine(moves: [move], minutes: 5, source: "library"),
            cooldown: V1SessionRoutine(moves: [move], minutes: 5, source: "library")
        )
        #expect(ActivityRoutinesReadout.line(both, said: [:]) == "À dire")
        #expect(ActivityRoutinesReadout.line(both, said: [.warmup: .done]) == "\(V1RoutineStatus.done.label) · —")
        #expect(
            ActivityRoutinesReadout.line(both, said: [.warmup: .done, .cooldown: .skipped])
                == "\(V1RoutineStatus.done.label) · \(V1RoutineStatus.skipped.label)"
        )

        // A recovery session carries no stretches: only the warm-up is spoken of.
        let warmupOnly = V1SessionRoutines(warmup: both.warmup, cooldown: V1SessionRoutine(moves: [], minutes: 0, source: "library"))
        #expect(ActivityRoutinesReadout.line(warmupOnly, said: [.warmup: .shortened]) == V1RoutineStatus.shortened.label)
    }

    @Test func aDaysSecondSessionDoesNotRepeatTheDay() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(PlanTimelineReadout.lead(day, rank: 0) == PlanTimelineReadout.dayLabel(day))
        #expect(PlanTimelineReadout.lead(day, rank: 1) == "2ᵉ séance")
        #expect(PlanTimelineReadout.lead(day, rank: 2) == "3ᵉ séance")
    }

    @Test func aTrendIsReadAtTheDayUnderTheFinger() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<5).map { CorpsPoint(date: start.addingTimeInterval(Double($0) * 86_400), value: 50 + Double($0)) }
        #expect(SanteTrendReadout.nearest(points, to: start.addingTimeInterval(86_400 * 2.4))?.value == 52)
        #expect(SanteTrendReadout.nearest(points, to: start.addingTimeInterval(-9_000))?.value == 50)
        #expect(SanteTrendReadout.nearest(points, to: .distantFuture)?.value == 54)
        #expect(SanteTrendReadout.nearest([], to: start) == nil)
        #expect(SanteReadout.reading(52, of: .restingHr) == SanteReadout.value(V1HealthMarker(key: .restingHr, value: 52, basis: .latest)))
    }
}
