import Foundation

/// What the history shows: a sport, a period, a word from the title. Applied to the list the
/// server already sent — it holds the whole history — so a filter never waits on the network.
nonisolated struct ActivityFilter: Equatable, Sendable {
    var sport: V1ActivityType?
    var period: Period = .all
    var effortTime: EffortTime = .any
    var query = ""

    /// How long the session lasted, in buckets an athlete thinks in.
    enum EffortTime: String, CaseIterable, Identifiable, Sendable {
        case any, short, medium, long, veryLong

        var id: String { rawValue }

        var label: String {
            switch self {
            case .any: String(localized: "Toutes les durées")
            case .short: String(localized: "Moins de 30 min")
            case .medium: String(localized: "30 min à 1 h")
            case .long: String(localized: "1 h à 2 h")
            case .veryLong: String(localized: "Plus de 2 h")
            }
        }

        /// Seconds, lower bound kept, upper bound dropped.
        private var seconds: Range<Double> {
            switch self {
            case .any: 0..<Double.infinity
            case .short: 0..<1_800
            case .medium: 1_800..<3_600
            case .long: 3_600..<7_200
            case .veryLong: 7_200..<Double.infinity
            }
        }

        /// A session without a duration is kept by no bucket but `any`.
        func keeps(_ duration: Double?) -> Bool {
            guard self != .any else { return true }
            guard let duration else { return false }
            return seconds.contains(duration)
        }
    }

    enum Period: String, CaseIterable, Identifiable, Sendable {
        case week, month, quarter, year, all

        var id: String { rawValue }

        var label: String {
            switch self {
            case .week: String(localized: "7 derniers jours")
            case .month: String(localized: "30 derniers jours")
            case .quarter: String(localized: "3 derniers mois")
            case .year: String(localized: "12 derniers mois")
            case .all: String(localized: "Tout l’historique")
            }
        }

        /// The first day it keeps, nil for the whole history.
        func start(now: Date, calendar: Calendar) -> Date? {
            let today = calendar.startOfDay(for: now)
            switch self {
            case .week: return calendar.date(byAdding: .day, value: -6, to: today)
            case .month: return calendar.date(byAdding: .day, value: -29, to: today)
            case .quarter: return calendar.date(byAdding: .month, value: -3, to: today)
            case .year: return calendar.date(byAdding: .year, value: -1, to: today)
            case .all: return nil
            }
        }
    }

    /// Sport, period or duration chosen; the search field shows its own state.
    var narrows: Bool { sport != nil || period != .all || effortTime != .any }

    var isActive: Bool { narrows || !trimmedQuery.isEmpty }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func apply(to activities: [V1ActivityListItem], now: Date = .now, calendar: Calendar = .current) -> [V1ActivityListItem] {
        let start = period.start(now: now, calendar: calendar)
        let words = trimmedQuery
        return activities.filter { activity in
            if let sport, activity.type != sport { return false }
            if let start, activity.date < start { return false }
            if !effortTime.keeps(activity.duration) { return false }
            if !words.isEmpty {
                let haystack = [activity.title, activity.type.label].compactMap { $0 }.joined(separator: " ")
                if haystack.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
            }
            return true
        }
    }

    /// The sports the athlete actually did, the most frequent first — the menu offers no sport
    /// that would empty the list.
    static func sports(in activities: [V1ActivityListItem]) -> [V1ActivityType] {
        var counts: [V1ActivityType: Int] = [:]
        for activity in activities { counts[activity.type, default: 0] += 1 }
        return counts.keys.sorted { lhs, rhs in
            counts[lhs] != counts[rhs] ? counts[lhs]! > counts[rhs]! : lhs.label < rhs.label
        }
    }
}
