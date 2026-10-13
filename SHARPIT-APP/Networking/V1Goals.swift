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

/// A race's projected finish, computed server-side: the time, its range, each leg and where
/// its pace came from. Unknown values are tolerated: a leg of an unknown kind is dropped, an
/// unknown source or confidence reads nil.
nonisolated struct V1RaceProjection: Codable, Sendable, Equatable {
    nonisolated enum LegKind: String, Codable, Sendable { case swim, t1, bike, t2, run }
    nonisolated enum LegSource: String, Codable, Sendable { case history, recent, profile, `default` }
    nonisolated enum Confidence: String, Codable, Sendable { case low, medium, high }

    nonisolated struct Leg: Codable, Sendable, Equatable {
        let kind: LegKind
        let sec: Double
        var source: LegSource?

        enum CodingKeys: String, CodingKey { case kind, sec, source }

        init(kind: LegKind, sec: Double, source: LegSource? = nil) {
            self.kind = kind
            self.sec = sec
            self.source = source
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(LegKind.self, forKey: .kind)
            sec = try container.decode(Double.self, forKey: .sec)
            source = (try? container.decodeIfPresent(LegSource.self, forKey: .source)) ?? nil
        }
    }

    /// One week's race-day projection, as the server recorded it.
    nonisolated struct HistoryPoint: Codable, Sendable, Equatable {
        let weekKey: String
        let date: Date
        let finishSec: Double

        enum CodingKeys: String, CodingKey { case weekKey, date, finishSec }

        init(weekKey: String, date: Date, finishSec: Double) {
            self.weekKey = weekKey
            self.date = date
            self.finishSec = finishSec
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            weekKey = (try? container.decode(String.self, forKey: .weekKey)) ?? ""
            date = try Date.fromAPI(container.decode(String.self, forKey: .date))
            finishSec = try container.decode(Double.self, forKey: .finishSec)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(weekKey, forKey: .weekKey)
            try container.encode(date.toAPI, forKey: .date)
            try container.encode(finishSec, forKey: .finishSec)
        }
    }

    nonisolated struct Trend: Codable, Sendable, Equatable {
        /// Negative when getting faster.
        var secPerWeek: Double?
    }

    /// The projection at race day.
    let finishSec: Double
    let lowSec: Double
    let highSec: Double
    var targetSec: Double?
    /// Finish − target: negative when faster.
    var deltaSec: Double?
    var legs: [Leg]
    var confidence: Confidence?
    /// French hints on what would sharpen it, shown as-is.
    var missing: [String]
    /// Set once the projection was frozen before the race.
    var frozenAt: Date?
    /// The finish if the race were today.
    var todaySec: Double?
    /// Share of planned sessions done, 0...1.
    var regularity: Double?
    var trend: Trend?
    /// Weekly race-day projections, oldest first.
    var history: [HistoryPoint]

    enum CodingKeys: String, CodingKey {
        case finishSec, lowSec, highSec, targetSec, deltaSec, legs, confidence, missing, frozenAt
        case todaySec, regularity, trend, history
    }

    init(
        finishSec: Double,
        lowSec: Double,
        highSec: Double,
        targetSec: Double? = nil,
        deltaSec: Double? = nil,
        legs: [Leg] = [],
        confidence: Confidence? = nil,
        missing: [String] = [],
        frozenAt: Date? = nil,
        todaySec: Double? = nil,
        regularity: Double? = nil,
        trend: Trend? = nil,
        history: [HistoryPoint] = []
    ) {
        self.finishSec = finishSec
        self.lowSec = lowSec
        self.highSec = highSec
        self.targetSec = targetSec
        self.deltaSec = deltaSec
        self.legs = legs
        self.confidence = confidence
        self.missing = missing
        self.frozenAt = frozenAt
        self.todaySec = todaySec
        self.regularity = regularity
        self.trend = trend
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        finishSec = try container.decode(Double.self, forKey: .finishSec)
        lowSec = (try? container.decode(Double.self, forKey: .lowSec)) ?? finishSec
        highSec = (try? container.decode(Double.self, forKey: .highSec)) ?? finishSec
        targetSec = (try? container.decodeIfPresent(Double.self, forKey: .targetSec)) ?? nil
        deltaSec = (try? container.decodeIfPresent(Double.self, forKey: .deltaSec)) ?? nil
        legs = (try? container.decodeIfPresent(LossyRecordArray<Leg>.self, forKey: .legs))?.items ?? []
        confidence = (try? container.decodeIfPresent(Confidence.self, forKey: .confidence)) ?? nil
        missing = (try? container.decodeIfPresent(LossyRecordArray<String>.self, forKey: .missing))?.items ?? []
        frozenAt = ((try? container.decodeIfPresent(String.self, forKey: .frozenAt)) ?? nil).flatMap { try? Date.fromAPI($0) }
        todaySec = (try? container.decodeIfPresent(Double.self, forKey: .todaySec)) ?? nil
        regularity = (try? container.decodeIfPresent(Double.self, forKey: .regularity)) ?? nil
        trend = (try? container.decodeIfPresent(Trend.self, forKey: .trend)) ?? nil
        history = (try? container.decodeIfPresent(LossyRecordArray<HistoryPoint>.self, forKey: .history))?.items ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(finishSec, forKey: .finishSec)
        try container.encode(lowSec, forKey: .lowSec)
        try container.encode(highSec, forKey: .highSec)
        try container.encodeIfPresent(targetSec, forKey: .targetSec)
        try container.encodeIfPresent(deltaSec, forKey: .deltaSec)
        try container.encode(legs, forKey: .legs)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(missing, forKey: .missing)
        try container.encodeIfPresent(frozenAt?.toAPI, forKey: .frozenAt)
        try container.encodeIfPresent(todaySec, forKey: .todaySec)
        try container.encodeIfPresent(regularity, forKey: .regularity)
        try container.encodeIfPresent(trend, forKey: .trend)
        try container.encode(history, forKey: .history)
    }
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
    /// The server's finish projection; nil for a format it cannot project, or from an older server.
    var projection: V1RaceProjection?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, horizon, metricKey
        case startValue, currentValue, targetValue, unit, lowerIsBetter
        case targetDate, location, achieved, notes
        case priority, raceFormat, targetPerformance, createdAt
        case status, result, projection
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
        result: V1GoalRaceResult? = nil,
        projection: V1RaceProjection? = nil
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
        self.projection = projection
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
        projection = (try? container.decodeIfPresent(V1RaceProjection.self, forKey: .projection)) ?? nil
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
        try container.encodeIfPresent(projection, forKey: .projection)
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
