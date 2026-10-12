import Foundation

/// Priority of a race goal (triathlon standard):
/// A = Primary season goal, B = Intermediate race, C = Preparation / test race.
nonisolated enum GoalPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .a: "Objectif A (Principal)"
        case .b: "Course B (Intermédiaire)"
        case .c: "Test C (Préparation)"
        }
    }
}

nonisolated enum GoalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case race = "RACE"
    case metric = "METRIC"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .race: "Course / Compétition"
        case .metric: "Objectif chiffré"
        }
    }
}

nonisolated enum GoalHorizon: String, Codable, CaseIterable, Identifiable, Sendable {
    case shortTerm = "SHORT_TERM"
    case mediumTerm = "MEDIUM_TERM"
    case longTerm = "LONG_TERM"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"

    var id: String { rawValue }
}

/// Where a race stands, as the server reads it (`raceGoalStanding`): done once validated or
/// once its day has come with a session linked; past its day with neither, it awaits its result.
nonisolated enum GoalRaceStatus: String, Codable, Sendable {
    case upcoming, raceDay, done, awaitingResult
}

/// A race's result: the session linked to it and its time.
nonisolated struct V1GoalRaceResult: Codable, Sendable, Equatable {
    let activityId: String
    let durationSec: Double?
}

/// An athlete goal, as `/api/goals` returns it.
nonisolated struct V1Goal: Identifiable, Codable, Sendable, Equatable {
    let id: String
    var title: String
    var kind: GoalKind
    var horizon: GoalHorizon?
    var metricKey: String?
    var startValue: Double?
    var currentValue: Double?
    var targetValue: Double?
    var unit: String?
    var lowerIsBetter: Bool?
    var targetDate: Date?
    var location: String?
    var achieved: Bool
    var notes: String?
    var priority: GoalPriority?
    var raceFormat: String?
    var targetPerformance: String?
    var createdAt: Date?
    /// Nil for a figure goal, or from a server that predates it.
    var status: GoalRaceStatus?
    var result: V1GoalRaceResult?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, horizon, metricKey
        case startValue, currentValue, targetValue, unit, lowerIsBetter
        case targetDate, location, achieved, notes
        case priority, raceFormat, targetPerformance, createdAt
        case status, result
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        kind: GoalKind,
        horizon: GoalHorizon? = nil,
        metricKey: String? = nil,
        startValue: Double? = nil,
        currentValue: Double? = nil,
        targetValue: Double? = nil,
        unit: String? = nil,
        lowerIsBetter: Bool? = nil,
        targetDate: Date? = nil,
        location: String? = nil,
        achieved: Bool = false,
        notes: String? = nil,
        priority: GoalPriority? = nil,
        raceFormat: String? = nil,
        targetPerformance: String? = nil,
        createdAt: Date? = nil,
        status: GoalRaceStatus? = nil,
        result: V1GoalRaceResult? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.horizon = horizon
        self.metricKey = metricKey
        self.startValue = startValue
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.unit = unit
        self.lowerIsBetter = lowerIsBetter
        self.targetDate = targetDate
        self.location = location
        self.achieved = achieved
        self.notes = notes
        self.priority = priority
        self.raceFormat = raceFormat
        self.targetPerformance = targetPerformance
        self.createdAt = createdAt
        self.status = status
        self.result = result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(GoalKind.self, forKey: .kind)
        horizon = try container.decodeIfPresent(GoalHorizon.self, forKey: .horizon)
        metricKey = try container.decodeIfPresent(String.self, forKey: .metricKey)
        startValue = try container.decodeIfPresent(Double.self, forKey: .startValue)
        currentValue = try container.decodeIfPresent(Double.self, forKey: .currentValue)
        targetValue = try container.decodeIfPresent(Double.self, forKey: .targetValue)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        lowerIsBetter = try container.decodeIfPresent(Bool.self, forKey: .lowerIsBetter)
        if let rawDate = try container.decodeIfPresent(String.self, forKey: .targetDate) {
            targetDate = try? Date.fromAPI(rawDate)
        } else {
            targetDate = nil
        }
        location = try container.decodeIfPresent(String.self, forKey: .location)
        achieved = (try? container.decodeIfPresent(Bool.self, forKey: .achieved)) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        priority = try container.decodeIfPresent(GoalPriority.self, forKey: .priority)
        raceFormat = try container.decodeIfPresent(String.self, forKey: .raceFormat)
        targetPerformance = try container.decodeIfPresent(String.self, forKey: .targetPerformance)
        if let rawCreated = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = try? Date.fromAPI(rawCreated)
        } else {
            createdAt = nil
        }
        status = (try? container.decodeIfPresent(GoalRaceStatus.self, forKey: .status)) ?? nil
        result = (try? container.decodeIfPresent(V1GoalRaceResult.self, forKey: .result)) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(horizon, forKey: .horizon)
        try container.encodeIfPresent(metricKey, forKey: .metricKey)
        try container.encodeIfPresent(startValue, forKey: .startValue)
        try container.encodeIfPresent(currentValue, forKey: .currentValue)
        try container.encodeIfPresent(targetValue, forKey: .targetValue)
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encodeIfPresent(lowerIsBetter, forKey: .lowerIsBetter)
        try container.encodeIfPresent(targetDate?.toAPI, forKey: .targetDate)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(achieved, forKey: .achieved)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(raceFormat, forKey: .raceFormat)
        try container.encodeIfPresent(targetPerformance, forKey: .targetPerformance)
        try container.encodeIfPresent(createdAt?.toAPI, forKey: .createdAt)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(result, forKey: .result)
    }

    /// The server's reading, with a validation shown on the tap before it answers.
    var raceStatus: GoalRaceStatus? {
        guard kind == .race else { return nil }
        return achieved ? .done : status
    }

    /// Reached by hand, or a race run: listed under « Atteints ».
    var isReached: Bool {
        achieved || raceStatus == .done
    }

    /// The race's day has come — the server's rule for a session linked to it to make it done.
    var isRaceDayReached: Bool {
        (daysRemaining ?? 0) <= 0
    }

    /// Days remaining until targetDate, nil if no targetDate.
    var daysRemaining: Int? {
        guard let targetDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: targetDate)
        let components = calendar.dateComponents([.day], from: today, to: target)
        return components.day
    }

    /// Macro phase label derived from days remaining, matching the periodization in the web app:
    /// <= 7 days: Course
    /// <= 21 days: Affûtage
    /// <= 56 days: Spécifique
    /// > 56 days: Développement
    var phaseLabel: String? {
        guard let days = daysRemaining, days >= 0 else { return nil }
        if days <= 7 { return "Course" }
        if days <= 21 { return "Affûtage" }
        if days <= 56 { return "Spécifique" }
        return "Développement"
    }

    /// Full countdown label matching the web app: e.g. "J-19 jours restants"
    var countdownText: String? {
        guard let days = daysRemaining else { return nil }
        if days > 0 {
            return "J-\(days) jours restants"
        } else if days == 0 {
            return "Jour J"
        } else {
            return "Épreuve passée"
        }
    }

    /// Subtitle combining target performance and training phase (e.g. "Sub 6h · Affûtage")
    var performanceAndPhaseSubtitle: String? {
        let items = [targetPerformance, phaseLabel].compactMap { $0 }.filter { !$0.isEmpty }
        return items.isEmpty ? nil : items.joined(separator: " · ")
    }

    /// Progress fraction between 0.0 and 1.0 for metrics.
    var progressFraction: Double? {
        guard let current = currentValue, let target = targetValue else { return nil }
        let start = startValue ?? 0
        let total = target - start
        guard abs(total) > 0.0001 else { return 1.0 }
        let prog = (current - start) / total
        return min(max(prog, 0.0), 1.0)
    }
}

nonisolated struct CreateGoalInput: Codable, Sendable {
    var title: String
    var kind: GoalKind
    var priority: GoalPriority?
    var targetDate: Date?
    var location: String?
    var raceFormat: String?
    var targetPerformance: String?
    var targetValue: Double?
    var startValue: Double?
    var currentValue: Double?
    var unit: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case title, kind, priority, targetDate, location
        case raceFormat, targetPerformance, targetValue, startValue, currentValue, unit, notes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(targetDate?.toAPI, forKey: .targetDate)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(raceFormat, forKey: .raceFormat)
        try container.encodeIfPresent(targetPerformance, forKey: .targetPerformance)
        try container.encodeIfPresent(targetValue, forKey: .targetValue)
        try container.encodeIfPresent(startValue, forKey: .startValue)
        try container.encodeIfPresent(currentValue, forKey: .currentValue)
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

/// A session linked to a goal (`Activity.goalId`), as `GET /api/v1/goals/[id]` lists them,
/// newest first.
nonisolated struct V1GoalLinkedActivity: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let title: String?
    let type: V1ActivityType
    let date: Date
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, type, date, duration
    }

    init(id: String, title: String? = nil, type: V1ActivityType, date: Date, duration: Double? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.date = date
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = (try? container.decodeIfPresent(V1ActivityType.self, forKey: .type)) ?? .other
        date = try Date.fromAPI(container.decode(String.self, forKey: .date))
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
    }
}

/// `GET /api/v1/goals/[id]`, read only for its linked sessions: a server that predates the
/// link sends none.
nonisolated struct V1GoalDetailPayload: Decodable, Sendable {
    let activities: [V1GoalLinkedActivity]

    enum CodingKeys: String, CodingKey { case activities }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activities = (try? container.decodeIfPresent(LossyRecordArray<V1GoalLinkedActivity>.self, forKey: .activities))?.items ?? []
    }
}
