import Foundation
import Testing
@testable import Sharpit

// Figures the screens never expected: a division by zero upstream, a corrupt sample, a value
// beyond `Int`. Each formatter must read them as missing (« — ») rather than trap.

private let unreadable: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300]

@Test func activityFiguresReadUnreadableValuesAsMissing() {
    for value in unreadable {
        #expect(ActivityFormat.duration(value) == "—")
        #expect(ActivityFormat.paceClock(value) == "—")
        #expect(ActivityFormat.speedKmh(distanceM: value, duration: 3_600) == "—")
        #expect(ActivityFormat.trainingLoad(value, isExpertReading: true) == "0 TSS")
    }
    #expect(ActivityFormat.speedKmh(distanceM: 40_000, duration: 0) == "—")
    #expect(ActivityFormat.duration(-60) == "—")
}

@Test func activityFiguresKeepLongAndZeroSessionsReadable() {
    #expect(ActivityFormat.duration(0) == "0 min")
    #expect(ActivityFormat.duration(36 * 3_600 + 15 * 60) == "36 h 15 min")
    #expect(ActivityFormat.paceClock(0) == "0'00\"")
    #expect(ActivityFormat.paceClock(3_599.6) == "60'00\"")
    #expect(ActivityFormat.speedKmh(distanceM: 180_000, duration: 18_000) == "36,0")
}

@Test func sharedFiguresReadUnreadableValuesAsMissing() {
    for value in unreadable {
        #expect(SharpitFigureFormat.kcal(value) == "—")
        #expect(SharpitFigureFormat.remainingKcal(value) == nil)
        #expect(SharpitFigureFormat.target(value) == "— kg")
        #expect(SharpitFigureFormat.kilometers(value) == "—")
        #expect(SharpitFigureFormat.duration(minutes: value) == "—")
    }
    #expect(SharpitFigureFormat.kcal(123_456) == 123_456.formatted(.number.locale(AppLanguage.locale)))
    #expect(SharpitFigureFormat.kilometers(12_345.6) == 12_346.formatted(.number.locale(AppLanguage.locale)))
}

@Test func sleepFiguresReadUnreadableValuesAsMissing() {
    for value in unreadable {
        #expect(SleepReadout.duration(value) == "—")
        #expect(SleepReadout.delta(value) == nil)
        #expect(SleepReadout.scoreDelta(score: value, average: 70) == nil)
    }
    #expect(SleepReadout.duration(0) == "0 min")
}

@Test func strengthLoadsReadUnreadableValuesAsMissing() {
    for value in unreadable {
        #expect(GuidedStrengthSetTarget.kilograms(value) == "— kg")
        #expect(StrengthExerciseReadout.kilograms(value) == "— kg")
    }
    #expect(StrengthExerciseReadout.kilograms(0) == "0 kg")
    #expect(StrengthExerciseReadout.kilograms(1_250.25) == "1250,3 kg")
}
