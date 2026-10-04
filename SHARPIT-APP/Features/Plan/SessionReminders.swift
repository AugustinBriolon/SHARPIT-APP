import Foundation
import UserNotifications

/// A reminder of a planned session, before it happens.
struct SessionReminder: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

/// When and how each session ahead is announced — pure, so the rules are tested.
///
/// Local notifications, not pushes: the time comes from the plan already on the phone, fires to
/// the minute without a network, and costs no server schedule (Vercel Hobby runs a cron at most
/// once a day, within the hour).
enum SessionReminderPlanner {
    static let identifierPrefix = "session-reminder-"
    /// A session with a time is announced this long before it.
    static let leadTime: TimeInterval = 3600
    /// A session without one, this morning.
    static let morningHour = 7
    static let morningMinute = 30
    /// iOS keeps 64 pending notifications per app; the rest are the app's other uses.
    static let maximum = 20

    static func reminders(
        for sessions: [V1PlannedSessionItem],
        now: Date,
        calendar: Calendar = .current
    ) -> [SessionReminder] {
        sessions
            .filter { $0.completed != true && $0.activityId == nil }
            .compactMap { reminder(for: $0, calendar: calendar) }
            .filter { $0.fireDate > now }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maximum)
            .map { $0 }
    }

    private static func reminder(for session: V1PlannedSessionItem, calendar: Calendar) -> SessionReminder? {
        let day = calendar.startOfDay(for: session.date)
        let name = session.title ?? session.displayType
        let detail = [name, session.durationMin.map { "\($0) min" }].compactMap { $0 }.joined(separator: " · ")
        if let time = session.startTime.flatMap(clock), let start = calendar.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: day
        ) {
            return SessionReminder(
                id: identifierPrefix + session.id,
                fireDate: start.addingTimeInterval(-leadTime),
                title: "Ta séance t’attend à \(session.startTime ?? "")",
                body: detail
            )
        }
        guard let morning = calendar.date(bySettingHour: morningHour, minute: morningMinute, second: 0, of: day) else {
            return nil
        }
        return SessionReminder(id: identifierPrefix + session.id, fireDate: morning, title: "Ta séance du jour t’attend", body: detail)
    }

    private static func clock(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}

/// Keeps iOS's pending session reminders equal to the plan: every refresh replaces them all, so a
/// session moved, removed or done never rings.
@MainActor
final class SessionReminderScheduler {
    static let shared = SessionReminderScheduler()

    /// How far ahead the plan is read.
    static let horizonDays = 8

    private let center = UNUserNotificationCenter.current()

    /// Reads the athlete's switch and the plan, then reschedules. A failed read keeps what is
    /// scheduled: a stale reminder is better than none.
    func refresh(
        isEnabledOnPhone: Bool,
        profiles: any AthleteProfileServing,
        plan: any PlannedSessionServing,
        tokenProvider: () async throws -> String,
        now: Date = .now
    ) async {
        guard isEnabledOnPhone else {
            await clear()
            return
        }
        do {
            let token = try await tokenProvider()
            let wanted = try await profiles.athleteProfile(token: token).notificationPrefs?.sessionReminder ?? true
            guard wanted else {
                await clear()
                return
            }
            let horizon = Calendar.current.date(byAdding: .day, value: Self.horizonDays, to: now) ?? now
            let sessions = try await plan.plannedSessions(from: now, to: horizon, token: token)
            await schedule(SessionReminderPlanner.reminders(for: sessions, now: now))
        } catch {
            // Offline or signed out: leave the reminders already scheduled.
        }
    }

    func clear() async {
        center.removePendingNotificationRequests(withIdentifiers: await pendingIdentifiers())
    }

    private func schedule(_ reminders: [SessionReminder]) async {
        await clear()
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = "session-reminder"
            content.userInfo = ["url": "/plan"]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    private func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(SessionReminderPlanner.identifierPrefix) }
    }
}
