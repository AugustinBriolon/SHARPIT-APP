import Testing
@testable import Sharpit

private func plate(_ label: String, _ code: VerdictStateCode?) -> InkPlateModel {
    InkPlateModel(statusLabel: label, headline: "", estimationGaps: [], posture: .steady, stateCode: code)
}

@Test func aVerdictToEaseReadsAsWatchOnItsOwnWash() {
    let status = VerdictReadout.status(for: plate("Prudence", .caution))
    #expect(status == .watch)
    #expect(VerdictReadout.wash(for: status) == .watch)
}

@Test func aGoVerdictReadsAsGood() {
    #expect(VerdictReadout.status(for: plate("Feu vert", .trainHard)) == .good)
}

@Test func aVerdictWithoutDataIsUnknownOnTheNeutralWash() {
    let status = VerdictReadout.status(for: plate("Données insuffisantes", .insufficientData))
    #expect(status == .unknown)
    #expect(VerdictReadout.wash(for: status) == .neutral)
}

@Test func regularityCountsTheDaysWithAnActivity() {
    let days = [true, false, true].enumerated().map { index, active in
        V1TodayConsistencyDay(
            date: "2026-11-1\(index)", weekdayLabel: "L", dayOfMonth: 10 + index,
            hasActivity: active, isToday: false, isFuture: false
        )
    }
    let count = ResumeScoreReadout.activeDays(V1TodayConsistency(days: days, thisWeekSessionCount: 2))
    #expect(count.done == 2)
    #expect(count.of == 3)
}

@Test func theRecoveryCaptionNamesTheNervousSystem() {
    #expect(ResumeScoreReadout.caption("Frein · VFC", for: .recovery) == "Frein · Système nerveux")
    #expect(ResumeScoreReadout.caption("Nuit dernière · 6h 54m", for: .sleep) == "Nuit dernière · 6h 54m")
    #expect(ResumeScoreReadout.caption("", for: .sleep) == nil)
}

@Test func aLoadingRingHasNoScoreToDraw() {
    for gauge in OvernightGaugeModel.placeholders {
        #expect(AnimatedScoreText.progressFraction(from: gauge.score) == nil)
    }
}
