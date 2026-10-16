import Foundation

/// One month of the history: its sessions, newest first, and what they add up to.
nonisolated struct ActivityMonth: Identifiable, Equatable, Sendable {
    /// « 2026-10 » — a month of one year, so two Octobers never merge.
    let id: String
    let title: String
    let activities: [V1ActivityListItem]

    var durationSeconds: Double { activities.compactMap(\.duration).reduce(0, +) }

    /// « 12 séances · 14 h 20 ».
    var summary: String {
        let count = activities.count == 1 ? "1 séance" : "\(activities.count) séances"
        guard durationSeconds > 0 else { return count }
        return "\(count) · \(ActivityHistory.hours(durationSeconds))"
    }
}

/// The current week at a glance: how much, and on which days.
nonisolated struct ActivityWeekSummary: Equatable, Sendable {
    let count: Int
    let durationSeconds: Double
    let distanceM: Double
    /// Monday to Sunday: whether a session was done that day.
    let activeDays: [Bool]
    /// Monday to Sunday: whether the day is today.
    let todayIndex: Int
}

/// The history as Activité reads it, page by page: merged, cut into months, summed for the week.
nonisolated enum ActivityHistory {
    /// The sessions read so far and a newly read page, once each, newest first.
    static func merge(_ loaded: [V1ActivityListItem], with page: [V1ActivityListItem]) -> [V1ActivityListItem] {
        var seen = Set<String>()
        return (page + loaded)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
    }

    static func months(
        _ activities: [V1ActivityListItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ActivityMonth] {
        var order: [String] = []
        var byMonth: [String: [V1ActivityListItem]] = [:]
        for activity in activities.sorted(by: { $0.date > $1.date }) {
            let parts = calendar.dateComponents([.year, .month], from: activity.date)
            let key = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(activity)
        }
        let currentYear = calendar.component(.year, from: now)
        return order.map { key in
            let items = byMonth[key] ?? []
            return ActivityMonth(id: key, title: monthTitle(items[0].date, currentYear: currentYear, calendar: calendar), activities: items)
        }
    }

    static func week(
        _ activities: [V1ActivityListItem],
        now: Date = .now,
        calendar base: Calendar = .current
    ) -> ActivityWeekSummary {
        var calendar = base
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
        let thisWeek = activities.filter { $0.date >= start && $0.date < end }
        var activeDays = Array(repeating: false, count: 7)
        for activity in thisWeek {
            let index = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: activity.date)).day ?? 0
            if (0..<7).contains(index) { activeDays[index] = true }
        }
        let todayIndex = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
        return ActivityWeekSummary(
            count: thisWeek.count,
            durationSeconds: thisWeek.compactMap(\.duration).reduce(0, +),
            distanceM: thisWeek.compactMap(\.distanceM).reduce(0, +),
            activeDays: activeDays,
            todayIndex: todayIndex
        )
    }

    /// 51 600 s → « 14 h 20 », 2 400 s → « 40 min ».
    static func hours(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    /// « Octobre » this year, « Octobre 2025 » before.
    private static func monthTitle(_ date: Date, currentYear: Int, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(calendar.component(.year, from: date) == currentYear ? "MMMM" : "MMMM yyyy")
        return formatter.string(from: date).capitalized(with: Locale(identifier: "fr_FR"))
    }
}
