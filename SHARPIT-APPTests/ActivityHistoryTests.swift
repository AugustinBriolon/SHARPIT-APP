import Foundation
import Testing
@testable import Sharpit

// Activité reads its history page by page and lays it out by month, so years of sessions never
// load or render at once.

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func day(_ iso: String) -> Date { TrainingDayId.date(iso)! }

@Test func twoOctobersOfDifferentYearsStayApart() {
    let months = ActivityHistory.months([
        V1ActivityListItem(id: "a", date: day("2026-10-13"), duration: 3600),
        V1ActivityListItem(id: "b", date: day("2025-10-13"), duration: 1800),
        V1ActivityListItem(id: "c", date: day("2026-10-02"), duration: 1200),
    ], now: day("2026-10-16"), calendar: paris)

    #expect(months.map(\.id) == ["2026-10", "2025-10"])
    #expect(months.map(\.title) == ["Octobre", "Octobre 2025"])
    #expect(months[0].summary == "2 séances · 1 h 20")
}

@Test func aNewPageJoinsTheListOnceAndInOrder() {
    let loaded = [V1ActivityListItem(id: "a", date: day("2026-10-13")), V1ActivityListItem(id: "b", date: day("2026-09-01"))]
    let page = [V1ActivityListItem(id: "b", date: day("2026-09-01")), V1ActivityListItem(id: "c", date: day("2026-08-01"))]

    #expect(ActivityHistory.merge(loaded, with: page).map(\.id) == ["a", "b", "c"])
}

@Test func theWeekCountsMondayToSundayOnly() {
    // Friday 16 October 2026: the week runs from Monday 12.
    let week = ActivityHistory.week([
        V1ActivityListItem(id: "a", date: day("2026-10-16"), duration: 2400),
        V1ActivityListItem(id: "b", date: day("2026-10-13"), duration: 3480),
        V1ActivityListItem(id: "c", date: day("2026-10-11"), duration: 9999),
    ], now: day("2026-10-16"), calendar: paris)

    #expect(week.count == 2)
    #expect(week.activeDays == [false, true, false, false, true, false, false])
    #expect(week.todayIndex == 4)
    #expect(ActivityHistory.hours(week.durationSeconds) == "1 h 38")
}
