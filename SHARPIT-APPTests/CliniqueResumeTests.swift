import Testing
@testable import Sharpit

private func plate(_ label: String, _ code: VerdictStateCode?) -> InkPlateModel {
    InkPlateModel(statusLabel: label, headline: "", estimationGaps: [], posture: .steady, stateCode: code)
}

@Test func aVerdictToEaseReadsAsWatchOnItsOwnWash() {
    let status = CliniqueResumeReadout.status(for: plate("Prudence", .caution))
    #expect(status == .watch)
    #expect(CliniqueResumeReadout.wash(for: status) == .watch)
}

@Test func aGoVerdictReadsAsGood() {
    #expect(CliniqueResumeReadout.status(for: plate("Feu vert", .trainHard)) == .good)
}

@Test func aVerdictWithoutDataIsUnknownOnTheNeutralWash() {
    let status = CliniqueResumeReadout.status(for: plate("Données insuffisantes", .insufficientData))
    #expect(status == .unknown)
    #expect(CliniqueResumeReadout.wash(for: status) == .neutral)
}

@Test func aScoreBecomesARingFractionAndADashBecomesNoData() {
    #expect(CliniqueResumeReadout.fraction(score: "64") == 0.64)
    #expect(CliniqueResumeReadout.fraction(score: "—") == nil)
    #expect(CliniqueResumeReadout.fraction(score: "") == nil)
}

@Test func regularityCountsTheDaysWithAnActivity() {
    let days = [true, false, true].enumerated().map { index, active in
        V1TodayConsistencyDay(
            date: "2026-11-1\(index)", weekdayLabel: "L", dayOfMonth: 10 + index,
            hasActivity: active, isToday: false, isFuture: false
        )
    }
    let count = CliniqueResumeReadout.activeDays(V1TodayConsistency(days: days, thisWeekSessionCount: 2))
    #expect(count.done == 2)
    #expect(count.of == 3)
}
