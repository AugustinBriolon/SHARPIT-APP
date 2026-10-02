import Foundation

nonisolated struct V1TodayResponse: Codable, Sendable, Equatable {
    var apiVersion: Int
    var trainingDayId: String
    var empty: V1TodayEmpty?
    var verdict: V1TodayVerdict
    var weather: V1TodayWeather?
    var sessions: [V1TodaySession]
    var signals: [V1TodaySignal]
    /// Optional so a snapshot cached before this field existed still decodes.
    var consistency: V1TodayConsistency? = nil
    /// The night's proposal for today's session while it waits for an answer.
    var morningProposal: V1TodayMorningProposal? = nil
}

/// The morning recalibration the server proposes after the check-in: today's session eased
/// (`down`) or raised (`up`), answered through `/api/v1/morning-recalibration/action`.
nonisolated struct V1TodayMorningProposal: Codable, Sendable, Equatable {
    enum Direction: String, Codable, Sendable { case down = "DOWN", up = "UP" }

    struct Side: Codable, Sendable, Equatable {
        var intensityLabel: String?
        var durationMin: Int?
        var description: String?
    }

    /// False until the morning check-in, which refines the proposal; absent reads as done.
    var checkInDone: Bool? = nil
    var decisionId: String
    var sessionId: String
    var direction: Direction
    var changeSummary: String
    var why: String
    var from: Side
    var to: Side
}

/// Regularity, computed server-side from the athlete's recent activities.
///
/// The web derives the same window in the browser; both read one calculation so the two
/// surfaces cannot disagree about which days are marked.
nonisolated struct V1TodayConsistency: Codable, Sendable, Equatable {
    var days: [V1TodayConsistencyDay]
    var thisWeekSessionCount: Int
}

nonisolated struct V1TodayConsistencyDay: Codable, Sendable, Equatable, Identifiable {
    /// `yyyy-MM-dd`, and unique within the window.
    var date: String
    var weekdayLabel: String
    var dayOfMonth: Int
    var hasActivity: Bool
    var isToday: Bool
    var isFuture: Bool

    var id: String { date }
}

nonisolated struct V1TodayEmpty: Codable, Sendable, Equatable {
    var title: String
    var message: String?
    var code: V1TodayEmptyCode
    var webURL: String
}

nonisolated enum V1TodayEmptyCode: String, Codable, Sendable {
    case noContent = "NO_CONTENT"
}

nonisolated struct V1TodayVerdict: Codable, Sendable, Equatable {
    var eyebrow: String
    var headline: String
    var subline: String
    var posture: V1TodayPosture
    var confidencePct: Int?
    var limitingCause: String?
    var statusLabel: String? = nil
    var actionLine: String? = nil
    var confidenceLabel: String? = nil
    var packTier: V1TodayPackTier? = nil
    var estimationGaps: [String]? = nil
}

nonisolated enum V1TodayPackTier: String, Codable, Sendable {
    case full = "FULL"
    case partial = "PARTIAL"
    case low = "LOW"
    case insufficient = "INSUFFICIENT"
}


nonisolated struct V1TodayWeather: Codable, Sendable, Equatable {
    var city: String
    var tempC: Double
    var condition: String
}

nonisolated struct V1TodaySession: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var kind: V1TodaySessionKind
    var title: String
    var subtitle: String?
    var metrics: [V1TodayMetric]
    var sport: String? = nil
    var priority: Bool? = nil
    /// The prescription this line stands for. Distinct from `id`: a brick line is
    /// identified by its group, so only this addresses the session itself.
    var plannedSessionId: String? = nil
    /// Set on a brick line: its legs in order, so the chain opens as one session.
    var brickLegs: [V1TodayBrickLeg]? = nil
    /// Set on a brick under way: seconds from each leg's end to the next's start (T2, …).
    var brickTransitionsSec: [Int?]? = nil
    /// Set on a brick line: the group that addresses the brick as a whole (its evaluation).
    /// `id` cannot: a done brick's `id` is its first activity, for older app builds.
    var brickGroupId: String? = nil
}

/// One leg of a brick line.
nonisolated struct V1TodayBrickLeg: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var type: String
    var title: String
    var durationMin: Int?
    /// Done, and by which activity: absent from servers that predate a brick under way.
    var completed: Bool? = nil
    var activityId: String? = nil
    /// What the leg actually was, with the athlete's notes; nil while only planned.
    var actual: V1TodayBrickLegActual? = nil
}

/// A done leg as its activity recorded it.
nonisolated struct V1TodayBrickLegActual: Codable, Sendable, Equatable {
    var durationSec: Int?
    var load: Double?
    var rpe: Int?
    var feeling: String?
}

nonisolated enum V1TodaySessionKind: String, Codable, Sendable {
    case planned
    case done
}

nonisolated struct V1TodayMetric: Codable, Sendable, Equatable {
    var label: String
    var value: String
    var unit: String
}

nonisolated struct V1TodaySignal: Codable, Sendable, Equatable, Identifiable {
    var key: V1TodaySignalKey
    var score: String
    var caption: String?

    var id: V1TodaySignalKey { key }
}

nonisolated enum V1TodaySignalKey: String, Codable, Sendable {
    case sleep
    case recovery
    case effort
    case adaptation
}

nonisolated enum TrainingDayId {
    static func today(in calendar: Calendar = .current, now: Date = .now) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return "1970-01-01"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Local midnight of the day, or nil when the id is not `yyyy-MM-dd`.
    static func date(_ trainingDayId: String) -> Date? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: trainingDayId)
    }

    static func displayName(_ trainingDayId: String) -> String {
        guard let date = date(trainingDayId) else {
            return "Résumé"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
}
