import Foundation

/// A done session as its form edits it — logged by hand, or one already recorded.
///
/// A value, so the form compares it with where it started: an edit carries only what changed
/// (`changes(from:)`). The contract is the web's `createActivitySchema` /
/// `updateActivitySchema`: the duration in seconds, the measures under the sport's own
/// metrics (`runMetrics`, `hikeMetrics`, …), the sets of a strength session as a whole list.
struct ActivityDraft: Equatable {
    /// The sports a session can be logged in by hand; a triathlon is recorded by a watch.
    static let sports: [V1ActivityType] = [.run, .bike, .swim, .strength, .hike, .other]

    var sport: V1ActivityType = .run
    var date: Date
    var title = ""
    var durationMin: Int? = 45
    /// Kilometres on land, metres in the water — as the athlete counts them.
    var distanceText = ""
    var elevationText = ""
    var avgHrText = ""
    var rpe: Int?
    var feeling: SessionFeeling?
    var notes = ""
    var exercises: [StrengthExerciseDraft] = []

    /// A session finished just now, an hour after it started.
    static func new(now: Date = .now) -> ActivityDraft {
        ActivityDraft(date: now.addingTimeInterval(-3600))
    }

    init(date: Date) {
        self.date = date
    }

    init(detail: V1ActivityDetail) {
        sport = detail.type
        date = detail.date
        title = detail.title ?? ""
        durationMin = detail.duration.map { Int(($0 / 60).rounded()) }
        if let distance = detail.distanceM {
            distanceText = detail.type == .swim ? Self.number(distance) : Self.number(distance / 1000, digits: 2)
        }
        elevationText = detail.elevationM.map { Self.number($0) } ?? ""
        avgHrText = detail.avgHr.map { Self.number($0) } ?? ""
        rpe = detail.rpe.map { Int($0.rounded()) }
        feeling = SessionFeeling(stored: detail.feeling)
        notes = detail.notes ?? ""
        exercises = detail.strengthSets.map {
            StrengthExerciseDraft(name: $0.exercise, sets: $0.sets, reps: $0.reps, weightKg: $0.weightKg)
        }
    }

    // MARK: - What the sport measures

    var measuresDistance: Bool { [.run, .swim, .hike].contains(sport) }
    var measuresElevation: Bool { [.run, .bike, .hike].contains(sport) }
    var measuresHeartRate: Bool { [.run, .hike].contains(sport) }
    var isStrength: Bool { sport == .strength }
    var distanceUnit: String { sport == .swim ? "m" : "km" }

    /// What keeps the form from being sent, worded for the athlete; nil when it can go.
    var missingRequirement: String? {
        if date > .now.addingTimeInterval(300) { return "Une séance faite ne peut pas être dans le futur." }
        if measuresDistance, !distanceText.isEmpty, distanceM == nil { return "La distance n’est pas un nombre." }
        if measuresElevation, !elevationText.isEmpty, Self.parse(elevationText) == nil { return "Le dénivelé n’est pas un nombre." }
        if measuresHeartRate, !avgHrText.isEmpty, Self.parse(avgHrText) == nil { return "La fréquence cardiaque n’est pas un nombre." }
        if isStrength, !exercises.contains(where: \.isNamed) { return "Ajoute au moins un exercice." }
        return nil
    }

    // MARK: - Payloads

    /// Every field, for `POST /api/v1/activities`.
    func creation() -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "type": .string(sport.rawValue),
            "date": .string(date.toAPI),
        ]
        fields["title"] = Self.text(title)
        fields["duration"] = durationSeconds
        fields["rpe"] = rpe.map { .number(Double($0)) } ?? .null
        fields["feeling"] = feeling.map { .string($0.storedValue) } ?? .null
        fields["notes"] = Self.text(notes)
        if let metrics = metrics(), let key = metricsKey {
            fields[key] = metrics
        }
        if isStrength {
            fields["strengthSets"] = strengthSets
        }
        return fields
    }

    /// The fields that differ from `original`, for `PATCH /api/v1/activities/[id]`.
    func changes(from original: ActivityDraft) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        let sportChanged = sport != original.sport
        if sportChanged { fields["type"] = .string(sport.rawValue) }
        if date != original.date { fields["date"] = .string(date.toAPI) }
        if title != original.title { fields["title"] = Self.text(title) }
        if durationMin != original.durationMin { fields["duration"] = durationSeconds }
        if rpe != original.rpe { fields["rpe"] = rpe.map { .number(Double($0)) } ?? .null }
        if feeling != original.feeling { fields["feeling"] = feeling.map { .string($0.storedValue) } ?? .null }
        if notes != original.notes { fields["notes"] = Self.text(notes) }

        // A new sport takes its measures whole; the same sport only the ones that moved.
        if let key = metricsKey {
            let changed = sportChanged ? metrics() : metrics(changedFrom: original)
            if let changed { fields[key] = changed }
        }
        // The server rewrites the sets from the list, and only reads them with the type.
        if isStrength, sportChanged || exercises != original.exercises {
            fields["type"] = .string(sport.rawValue)
            fields["strengthSets"] = strengthSets
        }
        return fields
    }

    private var durationSeconds: JSONValue {
        durationMin.map { .number(Double($0 * 60)) } ?? .null
    }

    private var metricsKey: String? {
        switch sport {
        case .run: "runMetrics"
        case .bike: "bikeMetrics"
        case .swim: "swimMetrics"
        case .hike: "hikeMetrics"
        default: nil
        }
    }

    private var distanceM: Double? {
        guard let value = Self.parse(distanceText) else { return nil }
        return sport == .swim ? value : value * 1000
    }

    /// The sport's measures; nil when none is given, so a session logged without them sends none.
    private func metrics(changedFrom original: ActivityDraft? = nil) -> JSONValue? {
        var object: [String: JSONValue] = [:]
        if measuresDistance, original.map({ $0.distanceText != distanceText }) ?? !distanceText.isEmpty {
            object["distanceM"] = distanceM.map(JSONValue.number) ?? .null
        }
        if measuresElevation, original.map({ $0.elevationText != elevationText }) ?? !elevationText.isEmpty {
            object["elevationM"] = Self.parse(elevationText).map(JSONValue.number) ?? .null
        }
        if measuresHeartRate, original.map({ $0.avgHrText != avgHrText }) ?? !avgHrText.isEmpty {
            object["avgHr"] = Self.parse(avgHrText).map { .number($0.rounded()) } ?? .null
        }
        return object.isEmpty ? nil : .object(object)
    }

    private var strengthSets: JSONValue {
        .array(exercises.filter(\.isNamed).enumerated().map { order, exercise in
            .object([
                "exercise": .string(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)),
                "sets": .number(Double(exercise.sets)),
                // A done set counts at least one repetition.
                "reps": .number(Double(max(exercise.reps, 1))),
                "weightKg": exercise.weightKg.map(JSONValue.number) ?? .null,
                "order": .number(Double(order)),
            ])
        })
    }

    // MARK: - Text

    /// Accepts the French decimal comma.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }

    static func number(_ value: Double, digits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func text(_ value: String) -> JSONValue {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .null : .string(trimmed)
    }
}
