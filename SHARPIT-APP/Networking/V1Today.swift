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
    /// A race goal's day, or the few days after it once a session is linked; absent from
    /// servers that predate it and on every other day.
    var race: V1TodayRace? = nil
    /// Garmin daily stress (ADR-079). Callers: TodayFold. API: GET /api/v1/today.
    var stress: V1TodayStress? = nil
    var energyBank: V1TodayEnergyBank? = nil
    var targetBand: V1TodayTargetBand? = nil
    /// Chronological day events. Callers: TodayTimelineStrip. API: GET /api/v1/today. User: fix all.
    var timeline: [V1DayTimelineEvent]? = nil
}

nonisolated struct V1DayTimelineEvent: Codable, Sendable, Equatable, Identifiable {
    var kind: String
    var minuteOfDay: Double?
    var title: String
    var detail: String?

    var id: String { "\(kind)-\(minuteOfDay.map { String(Int($0)) } ?? "x")-\(title)" }
}

nonisolated struct V1TodayStress: Codable, Sendable, Equatable {
    var value: Double
    var asOf: String
}

nonisolated struct V1TodayEnergyBank: Codable, Sendable, Equatable {
    var algorithmVersion: String
    var value: Double?
    var typicalBaseline: Double?
    var asOfMinuteOfDay: Int
    var series: [V1TodayEnergyBankPoint]
}

nonisolated struct V1TodayEnergyBankPoint: Codable, Sendable, Equatable {
    var minuteOfDay: Int
    var value: Double
}

nonisolated struct V1TodayTargetBand: Codable, Sendable, Equatable {
    var algorithmVersion: String
    var low: Double
    var high: Double
    var status: String?
}

/// The race moment Résumé leads with (`selectRaceMoment` server-side).
nonisolated struct V1TodayRace: Codable, Sendable, Equatable {
    var goalId: String
    var title: String
    var raceFormat: String?
    var targetPerformance: String?
    /// `yyyy-MM-dd`, the athlete's own day.
    var targetDate: String
    /// `raceDay` or `postRace`; kept as text so a phase this build does not know drops the
    /// card instead of the whole day.
    var phase: String
    var activity: V1TodayRaceActivity?
}

/// The session linked to the race goal, once there is one.
nonisolated struct V1TodayRaceActivity: Codable, Sendable, Equatable {
    var id: String
    var title: String?
    var durationSec: Double?
    /// Empty for a single-sport race.
    var legs: [V1MultisportLeg] = []

    init(id: String, title: String? = nil, durationSec: Double? = nil, legs: [V1MultisportLeg] = []) {
        self.id = id
        self.title = title
        self.durationSec = durationSec
        self.legs = legs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        durationSec = try container.decodeIfPresent(Double.self, forKey: .durationSec)
        legs = (try? container.decodeIfPresent([V1MultisportLeg].self, forKey: .legs)) ?? []
    }
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

/// Dual reading for the morning verdict explanation (ADR-023) — the client picks by displayMode.
nonisolated struct V1TodayExplanation: Codable, Sendable, Equatable {
    var essential: String
    var expert: String
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
    /// Additive (PR #154). Dual density — never Markdown.
    var explanation: V1TodayExplanation? = nil
    /// Additive. Short plain-text instruction (impératif tutoyé).
    var instruction: String? = nil
    /// Additive. Frein codes sorted by importance; unknown codes decode without failing.
    var limiterSignals: [LimiterSignalCode]? = nil
    /// Additive. First frein code (= `limiterSignals[0]` when present).
    var limiterSignal: LimiterSignalCode? = nil
    /// Additive. Compared to yesterday for this athlete only.
    var vsYesterdayLabel: String? = nil
    /// Additive. New clients hide the headline when false / empty (legacy keeps `headline`).
    var showHeadline: Bool? = nil
    /// Additive. Stable machine code for colour / icon.
    var stateCode: VerdictStateCode? = nil
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
    /// One of the week's key sessions (SHARPIT F2); absent from older payloads.
    var isKey: Bool? = nil
    /// Why the coach wrote this session — Decision Memory rationale; absent on older payloads.
    var rationale: String? = nil
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
    case stress
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
