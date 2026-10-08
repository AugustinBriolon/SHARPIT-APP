import Foundation

/// Pull-back rules: when an EventKit event exists for a planned session, its schedule wins over the plan.
nonisolated enum AppleCalendarPull {
    static let sharpitSessionURLPrefix = "sharpit://plan/session/"

    /// Session id embedded in a Sharpit calendar event URL, if any.
    static func sessionId(fromSharpitURL url: URL) -> String? {
        guard url.scheme == "sharpit", url.host == "plan" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "session", !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    /// Event deleted in EventKit after we had written it — clear schedule on the server (no apple event id in v1).
    static func shouldClearScheduleAfterCalendarDelete(
        wasOnWriteCalendar: Bool,
        wasSyncedBefore: Bool
    ) -> Bool {
        wasOnWriteCalendar || wasSyncedBefore
    }

    static func clearScheduleFields() -> PlannedSessionFields {
        var fields = PlannedSessionFields()
        fields.setStartTime(nil)
        return fields
    }

    /// The start to use when reconciling plan vs calendar; `event` wins when present.
    static func resolveStart(plan: Date, event: Date?) -> Date {
        event ?? plan
    }

    /// Athlete-local start implied by the planned session, or the day start when untimed.
    static func planStart(for session: V1PlannedSessionItem, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: session.date)
        if let clock = session.startTime.flatMap(parseClock),
           let start = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day) {
            return start
        }
        if session.startTime == nil { return day }
        return nil
    }

    static func scheduleDiffers(plan: Date, resolved: Date, tolerance: TimeInterval = 60) -> Bool {
        abs(plan.timeIntervalSince(resolved)) > tolerance
    }

    /// PATCH body when EventKit moved the session.
    static func patchFields(matching eventStart: Date, isAllDay: Bool, calendar: Calendar = .current) -> PlannedSessionFields {
        var fields = PlannedSessionFields()
        fields.setDay(calendar.startOfDay(for: eventStart), calendar: calendar)
        if isAllDay {
            fields.setStartTime(nil)
        } else {
            let parts = calendar.dateComponents([.hour, .minute], from: eventStart)
            fields.setStartTime(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))
        }
        return fields
    }

    private static func parseClock(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}
