import Foundation

nonisolated struct V1PlannedSessionItem: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let date: Date
    /// "HH:mm", athlete-local, when the session has a time — the coach places it in a free slot.
    let startTime: String?
    let title: String?
    let type: String?
    let durationMin: Int?
    let intensity: String?
    let load: Double?
    let notes: String?
    /// The written déroulé, as the athlete or the coach wrote it.
    let description: String?
    /// The strength exercises as the server stores them, kept whole: an edit sends back what
    /// it does not show (the watch's exercise, the movement's intent) untouched.
    let strengthPrescription: JSONValue?
    /// The structured endurance steps, kept only to know they exist — the app does not edit them.
    let endurancePrescription: JSONValue?
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
    /// Shared by the legs of one brick — a multisport chain done without a break.
    let brickGroupId: String?
    /// The leg's place in its brick, 0 first.
    let brickOrder: Int?
    /// One of the week's two or three key sessions (SHARPIT F2); false on payloads written
    /// before the field existed.
    let isKey: Bool
    /// Why the coach wrote this session — Decision Memory rationale; absent on older payloads.
    let rationale: String?

    enum CodingKeys: String, CodingKey {
        case id, date, startTime, title, type, durationMin, intensity, load, notes, breakdown
        case description, strengthPrescription, endurancePrescription
        case goalId, completed, activityId, activity, brickGroupId, brickOrder, isKey, rationale
        case garminWorkoutId, garminWorkoutScheduledDate, garminWorkoutPushedAt
    }

    init(
        id: String,
        date: Date,
        startTime: String? = nil,
        title: String? = nil,
        type: String? = nil,
        durationMin: Int? = nil,
        intensity: String? = nil,
        load: Double? = nil,
        notes: String? = nil,
        description: String? = nil,
        strengthPrescription: JSONValue? = nil,
        endurancePrescription: JSONValue? = nil,
        goalId: String? = nil,
        completed: Bool? = nil,
        activityId: String? = nil,
        activity: V1PlannedSessionActivitySummary? = nil,
        breakdown: V1PlannedSessionBreakdown? = nil,
        garminWorkoutId: String? = nil,
        garminWorkoutScheduledDate: String? = nil,
        garminWorkoutPushedAt: Date? = nil,
        brickGroupId: String? = nil,
        brickOrder: Int? = nil,
        isKey: Bool = false,
        rationale: String? = nil
    ) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.title = title
        self.type = type
        self.durationMin = durationMin
        self.intensity = intensity
        self.load = load
        self.notes = notes
        self.description = description
        self.strengthPrescription = strengthPrescription
        self.endurancePrescription = endurancePrescription
        self.goalId = goalId
        self.completed = completed
        self.activityId = activityId
        self.activity = activity
        self.breakdown = breakdown
        self.garminWorkoutId = garminWorkoutId
        self.garminWorkoutScheduledDate = garminWorkoutScheduledDate
        self.garminWorkoutPushedAt = garminWorkoutPushedAt
        self.brickGroupId = brickGroupId
        self.brickOrder = brickOrder
        self.isKey = isKey
        self.rationale = rationale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try Date.fromPlannedAPI(container.decode(String.self, forKey: .date))
        startTime = try? container.decodeIfPresent(String.self, forKey: .startTime)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        durationMin = try container.decodeIfPresent(Int.self, forKey: .durationMin)
        intensity = try container.decodeIfPresent(String.self, forKey: .intensity)
        load = try container.decodeIfPresent(Double.self, forKey: .load)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        strengthPrescription = Self.present(try? container.decodeIfPresent(JSONValue.self, forKey: .strengthPrescription))
        endurancePrescription = Self.present(try? container.decodeIfPresent(JSONValue.self, forKey: .endurancePrescription))
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
        brickGroupId = try container.decodeIfPresent(String.self, forKey: .brickGroupId)
        brickOrder = try container.decodeIfPresent(Int.self, forKey: .brickOrder)
        isKey = (try? container.decodeIfPresent(Bool.self, forKey: .isKey)) ?? false
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
    }

    func withGarminPush(
        workoutId: String?,
        scheduledDate: String?,
        pushedAt: Date?
    ) -> V1PlannedSessionItem {
        V1PlannedSessionItem(
            id: id,
            date: date,
            startTime: startTime,
            title: title,
            type: type,
            durationMin: durationMin,
            intensity: intensity,
            load: load,
            notes: notes,
            description: description,
            strengthPrescription: strengthPrescription,
            endurancePrescription: endurancePrescription,
            goalId: goalId,
            completed: completed,
            activityId: activityId,
            activity: activity,
            breakdown: breakdown,
            garminWorkoutId: workoutId ?? garminWorkoutId,
            garminWorkoutScheduledDate: scheduledDate ?? garminWorkoutScheduledDate,
            garminWorkoutPushedAt: pushedAt ?? garminWorkoutPushedAt,
            brickGroupId: brickGroupId,
            brickOrder: brickOrder,
            isKey: isKey,
            rationale: rationale
        )
    }

    /// A JSON `null` read as absent, so « has a prescription » is one nil check.
    private static func present(_ value: JSONValue?) -> JSONValue? {
        guard let value, value != .null else { return nil }
        return value
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

extension Date {
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
/// Encodable too: the app keeps the last one read per session (`ActivityDiskCache`).
nonisolated struct V1PlannedSessionBreakdown: Codable, Sendable, Hashable {
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

nonisolated struct V1PlannedSessionStep: Codable, Sendable, Hashable, Identifiable {
    let key: String
    let label: String
    let detail: String?
    let target: String?
    /// Steps sharing a group are done together, `repeatCount` times. Absent on payloads
    /// written before the field existed.
    let group: String?
    /// Repetitions of the group this step belongs to. 1 for a plain step.
    /// Named around Swift's `repeat` keyword; the wire key stays `repeat`.
    let repeatCount: Int
    let notes: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, detail, target, group, notes
        case repeatCount = "repeat"
    }

    init(
        key: String,
        label: String,
        detail: String? = nil,
        target: String? = nil,
        group: String? = nil,
        repeatCount: Int = 1,
        notes: String? = nil
    ) {
        self.key = key
        self.label = label
        self.detail = detail
        self.target = target
        self.group = group
        self.repeatCount = repeatCount
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        repeatCount = try container.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// Steps done together, `repeatCount` times. A plain step is a set of one, done once.
///
/// Listed flat, a 5 × (bloc + récup) reads as five blocks then five recoveries; gathered, it
/// reads as the block and its recovery, five times — which is what the athlete does.
nonisolated struct PlannedStepSet: Hashable, Identifiable, Sendable {
    let id: String
    let repeatCount: Int
    let steps: [V1PlannedSessionStep]

    var isRepeated: Bool { repeatCount > 1 }

    static func sets(from steps: [V1PlannedSessionStep]) -> [PlannedStepSet] {
        var sets: [PlannedStepSet] = []
        for step in steps {
            let group = groupKey(of: step)
            if let last = sets.last, last.id == group {
                sets[sets.count - 1] = PlannedStepSet(id: group, repeatCount: last.repeatCount, steps: last.steps + [step])
            } else {
                sets.append(PlannedStepSet(id: group, repeatCount: step.repeatCount, steps: [step]))
            }
        }
        return sets
    }

    /// The server's group, else — on a breakdown read before it sent one — the block half of
    /// an endurance key (`block-step`), for a repeated step only: a plain step stands alone.
    private static func groupKey(of step: V1PlannedSessionStep) -> String {
        if let group = step.group { return group }
        guard step.repeatCount > 1, let block = step.key.split(separator: "-").first else { return step.key }
        return "legacy-\(block)"
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
