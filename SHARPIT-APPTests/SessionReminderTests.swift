import Foundation
import Testing
@testable import Sharpit

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func day(_ value: String, hour: Int = 12) -> Date {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    return paris.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
}

private func session(
    _ id: String,
    on date: String,
    at startTime: String? = nil,
    completed: Bool? = nil,
    activityId: String? = nil
) -> V1PlannedSessionItem {
    V1PlannedSessionItem(
        id: id, date: day(date), startTime: startTime, title: "Seuil", type: "RUN",
        durationMin: 55, completed: completed, activityId: activityId
    )
}

@Test func aTimedSessionIsAnnouncedAnHourBefore() {
    let reminders = SessionReminderPlanner.reminders(
        for: [session("s1", on: "2026-09-30", at: "18:00")],
        now: day("2026-09-28"),
        calendar: paris
    )

    #expect(reminders.count == 1)
    #expect(reminders[0].fireDate == paris.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 17)))
    #expect(reminders[0].title == "Séance à 18:00")
    #expect(reminders[0].body == "Seuil · 55 min")
    #expect(reminders[0].id == "session-reminder-s1")
}

@Test func aSessionWithoutATimeIsAnnouncedThatMorning() {
    let reminders = SessionReminderPlanner.reminders(
        for: [session("s1", on: "2026-09-30")],
        now: day("2026-09-28"),
        calendar: paris
    )

    #expect(reminders.first?.fireDate == paris.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 7, minute: 30)))
    #expect(reminders.first?.title == "Séance aujourd'hui")
}

@Test func aSessionDoneOrPastIsNeverAnnounced() {
    let reminders = SessionReminderPlanner.reminders(
        for: [
            session("done", on: "2026-09-30", completed: true),
            session("linked", on: "2026-09-30", activityId: "a1"),
            session("past", on: "2026-09-28", at: "08:00"),
            session("ahead", on: "2026-10-01", at: "07:00"),
        ],
        now: day("2026-09-28"),
        calendar: paris
    )

    #expect(reminders.map(\.id) == ["session-reminder-ahead"])
}

@Test func aMalformedTimeFallsBackToTheMorning() {
    let reminders = SessionReminderPlanner.reminders(
        for: [session("s1", on: "2026-09-30", at: "soir")],
        now: day("2026-09-28"),
        calendar: paris
    )
    #expect(reminders.first?.title == "Séance aujourd'hui")
}
