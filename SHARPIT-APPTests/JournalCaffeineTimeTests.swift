import Foundation
import Testing
@testable import Sharpit

/// The last coffee's time (SHARPIT ADR-138): now by default, the athlete's when they change it.
@Suite struct JournalCaffeineTimeTests {
    @Test func aCoffeeAddedTodayIsHadNow() {
        #expect(JournalStore.caffeineMinute(previousMg: 0, newMg: 60, kept: nil, isToday: true, nowMinute: 13 * 60) == 13 * 60)
        // A second coffee moves the time to it.
        #expect(JournalStore.caffeineMinute(previousMg: 60, newMg: 120, kept: 8 * 60, isToday: true, nowMinute: 16 * 60) == 16 * 60)
    }

    @Test func aCoffeeAddedToAnotherDayHasNoHourToAssume() {
        #expect(JournalStore.caffeineMinute(previousMg: 0, newMg: 60, kept: nil, isToday: false, nowMinute: 13 * 60) == nil)
    }

    @Test func aLowerTotalKeepsTheTimeAndNoneLeftClearsIt() {
        #expect(JournalStore.caffeineMinute(previousMg: 120, newMg: 60, kept: 10 * 60, isToday: true, nowMinute: 18 * 60) == 10 * 60)
        #expect(JournalStore.caffeineMinute(previousMg: 60, newMg: 0, kept: 10 * 60, isToday: true, nowMinute: 18 * 60) == nil)
    }

    @Test func theTimeGoesOutAndComesBack() throws {
        let sent = try JSONEncoder().encode(V1DayJournalEntry(trainingDayId: "2026-11-21", caffeineMg: 80, caffeineMinute: 16 * 60))
        let body = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body["caffeineMinute"] as? Int == 960)
        let read = try JSONDecoder().decode(V1DayJournalEntry.self, from: sent)
        #expect(read.caffeineMinute == 960)
        // No time known: nothing is sent, the server keeps or assumes it.
        let untimed = try JSONEncoder().encode(V1DayJournalEntry(trainingDayId: "2026-11-21", caffeineMg: 80))
        let untimedBody = try #require(try JSONSerialization.jsonObject(with: untimed) as? [String: Any])
        #expect(untimedBody["caffeineMinute"] == nil)
    }
}
