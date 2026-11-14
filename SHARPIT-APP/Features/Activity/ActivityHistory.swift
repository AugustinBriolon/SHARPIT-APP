import Foundation

/// One week of the history: its sessions, newest first, and what they add up to.
nonisolated struct ActivityWeek: Identifiable, Equatable, Sendable {
    /// The week's Monday, « 2026-11-09 ».
    let id: String
    /// « Cette semaine », « Semaine du 3 novembre ».
    let title: String
    let activities: [V1ActivityListItem]

    var durationSeconds: Double { activities.compactMap(\.duration).reduce(0, +) }

    /// « 4 séances · 6 h 40 ».
    var summary: String {
        let count = activities.count == 1 ? String(localized: "1 séance") : String(localized: "\(activities.count) séances")
        guard durationSeconds > 0 else { return count }
        return "\(count) · \(ActivityHistory.hours(durationSeconds))"
    }
}

/// The history as Activité reads it, page by page: merged, then cut into weeks.
nonisolated enum ActivityHistory {
    /// The sessions read so far and a newly read page, once each, newest first.
    static func merge(_ loaded: [V1ActivityListItem], with page: [V1ActivityListItem]) -> [V1ActivityListItem] {
        var seen = Set<String>()
        return (page + loaded)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
    }

    /// The sessions cut into weeks, Monday to Sunday, the newest first.
    static func weeks(
        _ activities: [V1ActivityListItem],
        now: Date = .now,
        calendar base: Calendar = .current
    ) -> [ActivityWeek] {
        var calendar = base
        calendar.firstWeekday = 2
        func monday(_ date: Date) -> Date {
            calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        }
        var order: [Date] = []
        var byWeek: [Date: [V1ActivityListItem]] = [:]
        for activity in activities.sorted(by: { $0.date > $1.date }) {
            let start = monday(activity.date)
            if byWeek[start] == nil { order.append(start) }
            byWeek[start, default: []].append(activity)
        }
        let thisWeek = monday(now)
        let currentYear = calendar.component(.year, from: now)
        return order.map { start in
            let parts = calendar.dateComponents([.year, .month, .day], from: start)
            return ActivityWeek(
                id: String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                title: start == thisWeek
                    ? String(localized: "Cette semaine")
                    : String(localized: "Semaine du \(weekDay(start, currentYear: currentYear, calendar: calendar))"),
                activities: byWeek[start] ?? []
            )
        }
    }

    /// 51 600 s → « 14 h 20 », 2 400 s → « 40 min ».
    static func hours(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    /// « 3 novembre » this year, « 3 novembre 2025 » before.
    private static func weekDay(_ date: Date, currentYear: Int, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(calendar.component(.year, from: date) == currentYear ? "d MMMM" : "d MMMM yyyy")
        return formatter.string(from: date)
    }
}
