import Foundation
import Testing
@testable import Sharpit

private func at(_ hour: Int, _ minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: hour, minute: minute))!
}

private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

@Test func theRessentiNeverOpensInTheNight() {
    #expect(!RessentiPromptTiming.isDue(now: at(0, 10), hasLastNightSleep: true, calendar: paris))
    #expect(!RessentiPromptTiming.isDue(now: at(5, 59), hasLastNightSleep: true, calendar: paris))
}

@Test func theRessentiWaitsForTheNightOrTenOClock() {
    #expect(RessentiPromptTiming.isDue(now: at(6, 30), hasLastNightSleep: true, calendar: paris))
    #expect(!RessentiPromptTiming.isDue(now: at(7, 0), hasLastNightSleep: false, calendar: paris))
    #expect(RessentiPromptTiming.isDue(now: at(10, 5), hasLastNightSleep: false, calendar: paris))
}

@Test func aSleepGaugeWithoutAFigureIsNotANight() {
    let pending = [OvernightGaugeModel(key: .sleep, score: "—", caption: nil)]
    let synced = [OvernightGaugeModel(key: .sleep, score: "82", caption: nil)]
    #expect(!RessentiPromptTiming.hasLastNightSleep(pending))
    #expect(RessentiPromptTiming.hasLastNightSleep(synced))
    #expect(!RessentiPromptTiming.hasLastNightSleep([OvernightGaugeModel(key: .recovery, score: "70", caption: nil)]))
}
