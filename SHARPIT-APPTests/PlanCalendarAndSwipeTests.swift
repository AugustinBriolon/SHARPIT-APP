import Foundation
import Testing
@testable import Sharpit

@Suite struct PlanCalendarPlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func day(_ text: String) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    @Test func aTimedSessionTakesItsSlot() throws {
        let session = V1PlannedSessionItem(
            id: "s1", date: day("2026-10-06"), startTime: "18:30", title: "Seuil", type: "RUN", durationMin: 55
        )
        let event = try #require(PlanCalendarPlanner.events(for: [session], calendar: calendar).first)
        #expect(!event.isAllDay)
        #expect(calendar.component(.hour, from: event.start) == 18)
        #expect(event.end.timeIntervalSince(event.start) == 55 * 60)
        #expect(event.url.absoluteString == "sharpit://plan/session/s1")
        #expect(event.title == "Seuil")
    }

    @Test func anUntimedSessionIsAllDay() throws {
        let session = V1PlannedSessionItem(id: "s2", date: day("2026-10-07"), title: "Footing", type: "RUN")
        let event = try #require(PlanCalendarPlanner.events(for: [session], calendar: calendar).first)
        #expect(event.isAllDay)
        #expect(event.end.timeIntervalSince(event.start) == 86_400)
        #expect(event.notes == nil)
    }
}

@Suite struct DaySwipeTests {
    @Test func theLeftEdgeStaysBack() {
        #expect(DaySwipe.step(startX: 10, translation: CGSize(width: 200, height: 0)) == nil)
    }

    @Test func theMiddleTurnsTheDay() {
        #expect(DaySwipe.step(startX: 180, translation: CGSize(width: 120, height: 10)) == .previous)
        #expect(DaySwipe.step(startX: 180, translation: CGSize(width: -120, height: 10)) == .next)
    }

    @Test func aShortOrMostlyVerticalSwipeScrolls() {
        #expect(DaySwipe.step(startX: 180, translation: CGSize(width: 40, height: 0)) == nil)
        #expect(DaySwipe.step(startX: 180, translation: CGSize(width: 90, height: 80)) == nil)
    }

    @Test func neverPastToday() {
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(DaySwipe.day(after: .next, from: today, today: today) == nil)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        #expect(DaySwipe.day(after: .next, from: yesterday, today: today) != nil)
        #expect(DaySwipe.day(after: .previous, from: today, today: today) == yesterday)
    }

    @Test func aFlickTurnsTheDayOnlyTheWayItWasThrown() {
        let short = CGSize(width: -30, height: 2)
        #expect(DaySwipe.step(startX: 180, translation: short, predictedEnd: CGSize(width: -260, height: 0)) == .next)
        #expect(DaySwipe.step(startX: 180, translation: short, predictedEnd: CGSize(width: 260, height: 0)) == nil)
        #expect(DaySwipe.step(startX: 180, translation: short, predictedEnd: CGSize(width: -80, height: 0)) == nil)
    }

    @Test func thePageFollowsTheFingerAndHoldsBackWhereNoDayLies() {
        #expect(DaySwipe.offset(for: -120, canTurn: true, width: 390) == -120)
        let held = DaySwipe.offset(for: -120, canTurn: false, width: 390)
        #expect(held < 0 && held > -120)
        #expect(DaySwipe.offset(for: -2000, canTurn: false, width: 390) > -390)
    }

    @Test func aVerticalOrEdgeDragIsNotATurn() {
        #expect(DaySwipe.axis(startX: 180, translation: CGSize(width: 30, height: 40)) == .vertical)
        #expect(DaySwipe.axis(startX: 10, translation: CGSize(width: 80, height: 0)) == .vertical)
        #expect(DaySwipe.axis(startX: 180, translation: CGSize(width: 80, height: 10)) == .horizontal)
    }

    @Test func aPickedDayComesInFromItsSideOfTime() {
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
        #expect(DaySwipe.step(from: today, to: lastWeek) == .previous)
        #expect(DaySwipe.step(from: lastWeek, to: today) == .next)
        #expect(DaySwipe.step(from: today, to: today) == nil)
        #expect(DaySwipe.entrySign(.next) > 0)
        #expect(DaySwipe.entrySign(.previous) < 0)
    }
}

@Suite struct JournalDrivingTests {
    @Test func wordsTheMinutesLikeTheWeb() {
        #expect(JournalDrivingFormat.minutes(nil) == "— min")
        #expect(JournalDrivingFormat.minutes(45) == "45 min")
        #expect(JournalDrivingFormat.minutes(90) == "1 h 30")
        #expect(JournalDrivingFormat.minutes(120) == "2 h")
    }

    @Test func theMinutesTravelWithTheDay() throws {
        let entry = try JSONDecoder().decode(
            V1DayJournalEntry.self,
            from: Data(#"{ "trainingDayId": "2026-10-05", "factors": {}, "drivingMinutes": 75 }"#.utf8)
        )
        #expect(entry.drivingMinutes == 75)
        #expect(entry.hasAnyAnswer)
        let encoded = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        #expect(encoded.contains("\"drivingMinutes\":75"))
    }
}
