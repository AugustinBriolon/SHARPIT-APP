import Foundation
import Testing
@testable import Sharpit

@MainActor
@Test func aHistoryCalendarMarksDaysWithDataAndReadEmptyOnes() throws {
    let now = Date(timeIntervalSince1970: 1_792_224_000) // 2026-10-17
    let weeks = SharpitWeeks(offsets: -1...0, now: { now })
    let calendar = weeks.calendar
    let today = calendar.startOfDay(for: now)
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
    let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))

    let marks = SharpitCalendarMark.dataMarks(in: weeks, now: now) { day in
        if calendar.isDate(day, inSameDayAs: yesterday) { return true }
        if calendar.isDate(day, inSameDayAs: twoDaysAgo) { return false }
        return nil
    }

    #expect(marks[yesterday] == .filled)
    #expect(marks[twoDaysAgo] == .muted)
    #expect(marks[today] == nil)
}
