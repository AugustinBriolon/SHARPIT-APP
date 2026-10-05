import Foundation

/// What the history shows: a sport, a period, a word from the title. Applied to the list the
/// server already sent — it holds the whole history — so a filter never waits on the network.
nonisolated struct ActivityFilter: Equatable, Sendable {
    var sport: V1ActivityType?
    var period: Period = .all
    var query = ""

    enum Period: String, CaseIterable, Identifiable, Sendable {
        case week, month, quarter, year, all

        var id: String { rawValue }

        var label: String {
            switch self {
            case .week: "7 derniers jours"
            case .month: "30 derniers jours"
            case .quarter: "3 derniers mois"
            case .year: "12 derniers mois"
            case .all: "Tout l’historique"
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

    /// Sport or period chosen; the search field shows its own state.
    var narrows: Bool { sport != nil || period != .all }

    var isActive: Bool { narrows || !trimmedQuery.isEmpty }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func apply(to activities: [V1ActivityListItem], now: Date = .now, calendar: Calendar = .current) -> [V1ActivityListItem] {
        let start = period.start(now: now, calendar: calendar)
        let words = trimmedQuery
        return activities.filter { activity in
            if let sport, activity.type != sport { return false }
            if let start, activity.date < start { return false }
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
