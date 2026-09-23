import Foundation

nonisolated struct V1PlannedSessionItem: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let date: Date
    let title: String?
    let type: String?
    let durationMin: Int?
    let intensity: String?
    let load: Double?
    let notes: String?
    let goalId: String?
    let completed: Bool?
    let activityId: String?
    let activity: V1PlannedSessionActivitySummary?
    /// What to actually do, with endurance targets already resolved against the athlete's
    /// thresholds. Server-side, so the app cannot promise a band a watch push would not
    /// send. Absent on payloads written before the field existed.
    let breakdown: V1PlannedSessionBreakdown?
    /// Last Garmin Connect workout created from this session.
    let garminWorkoutId: String?
    let garminWorkoutScheduledDate: String?
    let garminWorkoutPushedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, date, title, type, durationMin, intensity, load, notes, breakdown
        case goalId, completed, activityId, activity
        case garminWorkoutId, garminWorkoutScheduledDate, garminWorkoutPushedAt
    }

    init(
        id: String,
        date: Date,
        title: String? = nil,
        type: String? = nil,
        durationMin: Int? = nil,
        intensity: String? = nil,
        load: Double? = nil,
        notes: String? = nil,
        goalId: String? = nil,
        completed: Bool? = nil,
        activityId: String? = nil,
        activity: V1PlannedSessionActivitySummary? = nil,
        breakdown: V1PlannedSessionBreakdown? = nil,
        garminWorkoutId: String? = nil,
        garminWorkoutScheduledDate: String? = nil,
        garminWorkoutPushedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.type = type
        self.durationMin = durationMin
        self.intensity = intensity
        self.load = load
        self.notes = notes
        self.goalId = goalId
        self.completed = completed
        self.activityId = activityId
        self.activity = activity
        self.breakdown = breakdown
        self.garminWorkoutId = garminWorkoutId
        self.garminWorkoutScheduledDate = garminWorkoutScheduledDate
        self.garminWorkoutPushedAt = garminWorkoutPushedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try Date.fromPlannedAPI(container.decode(String.self, forKey: .date))
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        durationMin = try container.decodeIfPresent(Int.self, forKey: .durationMin)
        intensity = try container.decodeIfPresent(String.self, forKey: .intensity)
        load = try container.decodeIfPresent(Double.self, forKey: .load)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        goalId = try container.decodeIfPresent(String.self, forKey: .goalId)
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed)
        activityId = try container.decodeIfPresent(String.self, forKey: .activityId)
        activity = try container.decodeIfPresent(V1PlannedSessionActivitySummary.self, forKey: .activity)
        breakdown = try container.decodeIfPresent(
            V1PlannedSessionBreakdown.self,
            forKey: .breakdown
        )
        if let stringId = try? container.decodeIfPresent(String.self, forKey: .garminWorkoutId) {
            garminWorkoutId = stringId
        } else if let intId = try? container.decodeIfPresent(Int.self, forKey: .garminWorkoutId) {
            garminWorkoutId = String(intId)
        } else {
            garminWorkoutId = nil
        }
        garminWorkoutScheduledDate = try container.decodeIfPresent(String.self, forKey: .garminWorkoutScheduledDate)
        if let pushedString = try container.decodeIfPresent(String.self, forKey: .garminWorkoutPushedAt) {
            garminWorkoutPushedAt = try? Date.fromPlannedAPI(pushedString)
        } else {
            garminWorkoutPushedAt = nil
        }
    }

    func withGarminPush(
        workoutId: String?,
        scheduledDate: String?,
        pushedAt: Date?
    ) -> V1PlannedSessionItem {
        V1PlannedSessionItem(
            id: id,
            date: date,
            title: title,
            type: type,
            durationMin: durationMin,
            intensity: intensity,
            load: load,
            notes: notes,
            goalId: goalId,
            completed: completed,
            activityId: activityId,
            activity: activity,
            breakdown: breakdown,
            garminWorkoutId: workoutId ?? garminWorkoutId,
            garminWorkoutScheduledDate: scheduledDate ?? garminWorkoutScheduledDate,
            garminWorkoutPushedAt: pushedAt ?? garminWorkoutPushedAt
        )
    }

    var displayType: String {
        switch type?.uppercased() {
        case "RUN": "Course"
        case "BIKE": "Vélo"
        case "SWIM": "Natation"
        case "STRENGTH": "Force"
        case "HIKE": "Randonnée"
        case "TRIATHLON": "Triathlon"
        default: type?.capitalized ?? "Séance"
        }
    }

    var symbolName: String {
        switch type?.uppercased() {
        case "RUN": "figure.run"
        case "BIKE": "bicycle"
        case "SWIM": "figure.pool.swim"
        case "STRENGTH": "figure.strengthtraining.traditional"
        case "HIKE": "figure.hiking"
        default: "figure.mind.and.body"
        }
    }
}

private extension Date {
    nonisolated static func fromPlannedAPI(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = fractional.date(from: value) ?? standard.date(from: value) {
            return date
        }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        if let date = day.date(from: value) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid planned session date"))
    }
}

/// A session's breakdown, resolved for reading.
///
/// Endurance and strength arrive as one row shape: the reader wants an ordered list of
/// what to do, not two vocabularies.
nonisolated struct V1PlannedSessionBreakdown: Decodable, Sendable, Hashable {
    let steps: [V1PlannedSessionStep]
    /// True when the session carried no structure and this was inferred from duration
    /// and intensity — worth saying, because the athlete did not write it.
    let derived: Bool
    /// Athlete-facing reasons a target could not be resolved.
    let warnings: [String]

    init(steps: [V1PlannedSessionStep], derived: Bool = false, warnings: [String] = []) {
        self.steps = steps
        self.derived = derived
        self.warnings = warnings
    }
}

nonisolated struct V1PlannedSessionStep: Decodable, Sendable, Hashable, Identifiable {
    let key: String
    let label: String
    let detail: String?
    let target: String?
    /// Repetitions of the group this step belongs to. 1 for a plain step.
    /// Named around Swift's `repeat` keyword; the wire key stays `repeat`.
    let repeatCount: Int
    let notes: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, detail, target, notes
        case repeatCount = "repeat"
    }

    init(
        key: String,
        label: String,
        detail: String? = nil,
        target: String? = nil,
        repeatCount: Int = 1,
        notes: String? = nil
    ) {
        self.key = key
        self.label = label
        self.detail = detail
        self.target = target
        self.repeatCount = repeatCount
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        repeatCount = try container.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

nonisolated struct V1PlannedSessionActivitySummary: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let duration: Double?
    let load: Double?
    let type: String?

    init(id: String, duration: Double? = nil, load: Double? = nil, type: String? = nil) {
        self.id = id
        self.duration = duration
        self.load = load
        self.type = type
    }
}
