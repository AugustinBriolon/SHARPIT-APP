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

    @Test func aStrengthSessionIsMirroredOnceIntoAppleHealth() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(StrengthWorkoutMirror.interval(start: start, end: start.addingTimeInterval(2_700))?.duration == 2_700)
        // Too short to be a workout, or a clock that went backwards: nothing is written.
        #expect(StrengthWorkoutMirror.interval(start: start, end: start.addingTimeInterval(30)) == nil)
        #expect(StrengthWorkoutMirror.interval(start: start, end: start.addingTimeInterval(-60)) == nil)

        // Read back from Santé, SharpIt's own workout is not imported a second time.
        #expect(StrengthWorkoutMirror.isOwn(sourceBundleIdentifier: "app.sharpit.ios", app: "app.sharpit.ios"))
        #expect(!StrengthWorkoutMirror.isOwn(sourceBundleIdentifier: "com.apple.health", app: "app.sharpit.ios"))
        #expect(!StrengthWorkoutMirror.isOwn(sourceBundleIdentifier: "app.sharpit.ios", app: nil))
    }

    @Test func aCoachProposalSaysWhatItsButtonDoesAndWhatBecameOfIt() {
        func proposal(_ tool: String, _ status: CoachProposal.Status) -> CoachProposal {
            CoachProposal(id: "p", toolType: tool, status: status, headline: "Seuil")
        }
        let create = proposal("tool-createPlannedSession", .awaiting(approvalId: "a"))
        let delete = proposal("tool-deletePlannedSession", .awaiting(approvalId: "a"))
        #expect(CoachProposalReadout.approve(create, confirming: false) == "Ajouter au plan")
        #expect(CoachProposalReadout.approve(delete, confirming: false) == "Supprimer la séance")
        #expect(CoachProposalReadout.approve(delete, confirming: true) == "Confirmer la suppression")

        #expect(CoachProposalReadout.facts("Course · 45 min · charge 60") == "Course · 45\u{00A0}min · charge\u{00A0}60")
        #expect(CoachProposalReadout.facts(nil) == nil)
        #expect(CoachProposalReadout.facts("") == nil)

        #expect(CoachProposalReadout.outcome(proposal("tool-createPlannedSession", .applied)).status == .good)
        #expect(CoachProposalReadout.outcome(proposal("tool-createPlannedSession", .refused)).isStruck)
        #expect(CoachProposalReadout.outcome(proposal("tool-createPlannedSession", .accepted)).isWorking)
        let failed = CoachProposalReadout.outcome(proposal("tool-updatePlannedSession", .failed("Créneau déjà pris")))
        #expect(failed.status == .alert)
        #expect(failed.detail == "Créneau déjà pris")
    }
}
