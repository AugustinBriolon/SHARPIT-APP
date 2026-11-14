import Foundation
import Testing
@testable import Sharpit

@Test func aShortNightReadsAsWatchAndAVeryShortOneAsAlert() {
    #expect(SleepSheetReadout.status(.adequate) == .good)
    #expect(SleepSheetReadout.status(.excellent) == .good)
    #expect(SleepSheetReadout.status(.insufficient) == .watch)
    #expect(SleepSheetReadout.status(.severelyInsufficient) == .alert)
    #expect(SleepSheetReadout.status(.pending) == .unknown)
}

@Test func theNightIsSaidAgainstItsNeed() {
    #expect(SleepSheetReadout.need(-70) == "1 h 10 de moins que ton besoin")
    #expect(SleepSheetReadout.need(25) == "25 min de plus que ton besoin")
    #expect(SleepSheetReadout.need(0.4) == nil)
    #expect(SleepSheetReadout.need(nil) == nil)
}

@Test func aStageIsAShareOfTheSleepNotOfTheTimeInBed() {
    let stages = V1SleepStages(deepMin: 60, remMin: 90, lightMin: 150, awakeMin: 40)
    #expect(SleepSheetReadout.share(60, of: stages) == "20 %")
    #expect(SleepSheetReadout.share(150, of: stages) == "50 %")
    #expect(SleepSheetReadout.share(nil, of: stages) == nil)
}

@Test func aNightWithNoStageHasNoShare() {
    let stages = V1SleepStages(deepMin: nil, remMin: nil, lightMin: nil, awakeMin: nil)
    #expect(SleepSheetReadout.share(60, of: stages) == nil)
}

@Test func theNightIsNamedByItsEveningAndItsCourseByItsClocks() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    let axis = SleepSheetReadout.axis(start: at(13, 23, 50), end: at(14, 5, 55), calendar: calendar)
    #expect(axis.map(\.label) == ["23 h 50", "2 h", "4 h", "5 h 55"])
    #expect(axis.first?.at == 0)
    #expect(axis.last?.at == 1)
    #expect(SleepSheetReadout.axis(start: at(14, 6, 0), end: at(14, 6, 0), calendar: calendar).isEmpty)
}

@Test func theStretchesAwakeAreCountedAndTheNightsAveraged() {
    let start = Date(timeIntervalSince1970: 0)
    func sample(_ stage: HealthSleepSample.Stage, _ index: Double) -> HealthSleepSample {
        HealthSleepSample(start: start.addingTimeInterval(index * 600), end: start.addingTimeInterval(index * 600 + 600), stage: stage)
    }
    #expect(SleepSheetReadout.awakenings([sample(.awake, 0), sample(.core, 1), sample(.awake, 2)]) == "2 fois")
    #expect(SleepSheetReadout.awakenings([sample(.deep, 0)]) == nil)
    #expect(SleepSheetReadout.average([420, 436]) == "7 h 08")
    #expect(SleepSheetReadout.average([]) == nil)
}
