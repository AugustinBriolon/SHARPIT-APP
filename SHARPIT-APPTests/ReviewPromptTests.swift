import Foundation
import Testing
@testable import Sharpit

private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

private func day(_ offset: Int, hour: Int = 9) -> Date {
    let start = paris.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: hour))!
    return paris.date(byAdding: .day, value: offset, to: start)!
}

/// An athlete who opened the app on the given days after the first.
private func used(on days: [Int]) -> ReviewPromptPolicy {
    days.reduce(ReviewPromptPolicy()) { $0.recordingUse(on: day($1), calendar: paris) }
}

@Test func theAppNeverAsksBeforeTheAthleteHasLivedWithIt() {
    // Three days of use but only a week old: too soon.
    #expect(!used(on: [0, 3, 7]).mayAsk(now: day(7), version: "1.1", calendar: paris))
    // Two weeks old but opened twice: too little.
    #expect(!used(on: [0, 14]).mayAsk(now: day(14), version: "1.1", calendar: paris))
    #expect(used(on: [0, 5, 14]).mayAsk(now: day(14), version: "1.1", calendar: paris))
}

@Test func aDayOpenedSeveralTimesCountsOnce() {
    let policy = [day(0, hour: 8), day(0, hour: 12), day(0, hour: 21)]
        .reduce(ReviewPromptPolicy()) { $0.recordingUse(on: $1, calendar: paris) }
    #expect(policy.activeDayCount == 1)
    #expect(policy.firstUseDay == "2026-12-01")
}

@Test func theAppAsksOnceAVersionAndNeverTwiceInFourMonths() {
    let asked = used(on: [0, 5, 14]).asking(at: day(14), version: "1.1")
    // Same version: never again.
    #expect(!asked.mayAsk(now: day(200), version: "1.1", calendar: paris))
    // A new version a month later: still too soon.
    #expect(!asked.mayAsk(now: day(44), version: "1.2", calendar: paris))
    // A new version four months later: allowed.
    #expect(asked.mayAsk(now: day(14 + ReviewPromptPolicy.minimumDaysBetweenAsks), version: "1.2", calendar: paris))
}

@MainActor
@Test func theCountIsTheAccountsAndGoesWithIt() throws {
    let defaults = try #require(UserDefaults(suiteName: "review-\(UUID().uuidString)"))
    ReviewPrompt.noteUse(defaults: defaults, now: day(0))
    ReviewPrompt.noteUse(defaults: defaults, now: day(2))
    #expect(ReviewPrompt.load(defaults).activeDayCount == 2)
    ReviewPrompt.erase(defaults)
    #expect(ReviewPrompt.load(defaults) == ReviewPromptPolicy())
}

@Test func onlyAWeekWithEveryPlannedSessionDoneIsFull() {
    #expect(WeeklyReviewReadout.isFull(V1WeeklyStats(sessionsDone: 5, sessionsPlanned: 5)))
    #expect(WeeklyReviewReadout.isFull(V1WeeklyStats(sessionsDone: 6, sessionsPlanned: 5)))
    #expect(!WeeklyReviewReadout.isFull(V1WeeklyStats(sessionsDone: 4, sessionsPlanned: 5)))
    #expect(!WeeklyReviewReadout.isFull(V1WeeklyStats(sessionsDone: 0, sessionsPlanned: 0)))
    #expect(!WeeklyReviewReadout.isFull(nil))
}
