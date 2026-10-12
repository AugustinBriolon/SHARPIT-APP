import Foundation
import UserNotifications

/// Local check-in reminders (hydratation / humeur / caféine) — on-device like session reminders.
/// Callers: RootView, SettingsPages. API: notificationPrefs.dayCheckIns.
/// User: "fix all" — go-all P2 scheduled check-ins.
struct DayCheckInReminder: Equatable {
    let id: String
    let hour: Int
    let minute: Int
    let title: String
    let body: String
}

enum DayCheckInReminderPlanner {
    static let identifierPrefix = "day-checkin-"
    static let slots: [DayCheckInReminder] = [
        DayCheckInReminder(
            id: identifierPrefix + "hydration",
            hour: 10, minute: 0,
            title: "Hydratation",
            body: "Note ton eau du matin dans le journal."
        ),
        DayCheckInReminder(
            id: identifierPrefix + "mood",
            hour: 14, minute: 0,
            title: "Humeur",
            body: "Un mot sur ton état — ça affine la lecture du Twin."
        ),
        DayCheckInReminder(
            id: identifierPrefix + "caffeine",
            hour: 16, minute: 0,
            title: "Caféine",
            body: "Dernière caféine ? Note-la avant le soir."
        ),
    ]
}

@MainActor
final class DayCheckInReminderScheduler {
    static let shared = DayCheckInReminderScheduler()

    private let center = UNUserNotificationCenter.current()

    func refresh(
        isEnabledOnPhone: Bool,
        profiles: any AthleteProfileServing,
        tokenProvider: () async throws -> String
    ) async {
        guard isEnabledOnPhone else {
            await clear()
            return
        }
        do {
            let token = try await tokenProvider()
            let wanted = try await profiles.athleteProfile(token: token).notificationPrefs?.dayCheckIns ?? true
            guard wanted else {
                await clear()
                return
            }
            await schedule(DayCheckInReminderPlanner.slots)
        } catch {
            // Offline: keep what is already scheduled.
        }
    }

    func clear() async {
        center.removePendingNotificationRequests(withIdentifiers: await pendingIdentifiers())
    }

    private func schedule(_ reminders: [DayCheckInReminder]) async {
        await clear()
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = "day-checkin"
            content.userInfo = ["url": "/journal"]
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await center.add(
                UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            )
        }
    }

    private func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(DayCheckInReminderPlanner.identifierPrefix) }
    }
}
