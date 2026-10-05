import Foundation

/// A planned session as its form edits it.
///
/// A value, so the form compares it with where it started: « Enregistrer » stays off until
/// something changed, and the write carries only what did (`changes(from:)`).
struct PlannedSessionDraft: Equatable {
    /// The sports a session can be planned in by hand. A triathlon is a brick of legs, which
    /// the coach plans; a single leg is one of these.
    static let sports: [V1ActivityType] = [.run, .bike, .swim, .strength, .hike, .other]

    var sport: V1ActivityType
    /// Local midnight of the day.
    var day: Date
    /// Nil when the session has no set hour — the server's `startTime` is optional.
    var startTime: Date?
    var title: String
    var durationMin: Int?
    var intensity: PlannedSessionIntensity?
    /// The endurance déroulé, written. Required by the server for every sport but strength.
    var description: String
    /// Strength's exercises, required by the server for a strength session.
    var exercises: [StrengthExerciseDraft]
    /// The session already carries structured endurance steps the form does not edit.
    var hasStructuredSteps: Bool

    static let defaultDurationMin = 45

    /// A new session on `day`, with nothing written yet.
    static func new(on day: Date, calendar: Calendar = .current) -> PlannedSessionDraft {
        PlannedSessionDraft(
            sport: .run,
            day: calendar.startOfDay(for: day),
            startTime: nil,
            title: "",
            durationMin: defaultDurationMin,
            intensity: .endurance,
            description: "",
            exercises: [],
            hasStructuredSteps: false
        )
    }

    init(
        sport: V1ActivityType,
        day: Date,
        startTime: Date?,
        title: String,
        durationMin: Int?,
        intensity: PlannedSessionIntensity?,
        description: String,
        exercises: [StrengthExerciseDraft],
        hasStructuredSteps: Bool
    ) {
        self.sport = sport
        self.day = day
        self.startTime = startTime
        self.title = title
        self.durationMin = durationMin
        self.intensity = intensity
        self.description = description
        self.exercises = exercises
        self.hasStructuredSteps = hasStructuredSteps
    }

    init(session: V1PlannedSessionItem, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: session.date)
        self.init(
            sport: session.type.flatMap { V1ActivityType(rawValue: $0.uppercased()) } ?? .other,
            day: day,
            startTime: session.startTime.flatMap { PlannedSessionClock.date(from: $0, on: day, calendar: calendar) },
            title: session.title ?? "",
            durationMin: session.durationMin,
            intensity: session.intensity.flatMap { PlannedSessionIntensity(rawValue: $0.uppercased()) },
            description: session.description ?? "",
            exercises: StrengthExerciseDraft.exercises(in: session.strengthPrescription),
            hasStructuredSteps: session.endurancePrescription != nil
        )
    }

    var isStrength: Bool { sport == .strength }

    /// What the server would refuse, said before the athlete taps — nil once the draft can go.
    ///
    /// The server checks the déroulé (or the exercises) when a session is created or changes
    /// sport, never on another edit: a coach's session carries structured steps and no prose,
    /// and moving it or shortening it must not ask for a text it never needed.
    func missingRequirement(editing original: PlannedSessionDraft? = nil) -> String? {
        if let original, original.sport == sport { return nil }
        if isStrength {
            return exercises.contains(where: \.isNamed) ? nil : "Ajoute au moins un exercice."
        }
        let written = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return written.isEmpty ? "Décris le déroulé de la séance." : nil
    }

    /// Every field, for a creation.
    func creation() -> PlannedSessionFields {
        var fields = PlannedSessionFields()
        fields.setType(sport)
        fields.setDay(day)
        fields.setStartTime(startTime.map(PlannedSessionClock.string))
        fields.setTitle(title)
        fields.setDurationMin(durationMin)
        fields.setIntensity(intensity)
        writeDetails(into: &fields)
        return fields
    }

    /// Only what changed since `original`.
    ///
    /// A change of sport sends the details with it: the server checks a session's déroulé (or
    /// its exercises) against its sport in the same write, and refuses a sport alone.
    func changes(from original: PlannedSessionDraft, calendar: Calendar = .current) -> PlannedSessionFields {
        var fields = PlannedSessionFields()
        if !calendar.isDate(day, inSameDayAs: original.day) { fields.setDay(day, calendar: calendar) }
        if startTime.map(PlannedSessionClock.string) != original.startTime.map(PlannedSessionClock.string) {
            fields.setStartTime(startTime.map(PlannedSessionClock.string))
        }
        if title != original.title { fields.setTitle(title) }
        if durationMin != original.durationMin { fields.setDurationMin(durationMin) }
        if intensity != original.intensity { fields.setIntensity(intensity) }
        if sport != original.sport {
            fields.setType(sport)
            writeDetails(into: &fields)
            if original.hasStructuredSteps { fields.clearEndurancePrescription() }
        } else if isStrength, exercises != original.exercises {
            fields.setStrengthPrescription(StrengthExerciseDraft.prescription(exercises))
        } else if !isStrength, description != original.description {
            fields.setDescription(description)
        }
        return fields
    }

    private func writeDetails(into fields: inout PlannedSessionFields) {
        if isStrength {
            fields.setStrengthPrescription(StrengthExerciseDraft.prescription(exercises))
        } else {
            fields.setDescription(description)
        }
    }
}

/// `HH:mm`, as the server keeps a session's hour.
enum PlannedSessionClock {
    static func string(_ time: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func date(from string: String, on day: Date, calendar: Calendar = .current) -> Date? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}

/// One strength exercise as the form edits it.
///
/// The server's set carries more than the form shows — the watch's exercise, the movement's
/// intent and pattern, a timed rest. Those travel in `preserved` and go back untouched, so an
/// edit never strips what the coach wrote. Renaming the exercise drops the two that name the
/// old one (`garmin`, `exerciseCatalogId`): the server resolves the new name itself.
struct StrengthExerciseDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var sets: Int
    var reps: Int
    var weightKg: Double?
    private var preserved: [String: JSONValue]
    private let originalName: String

    static let setsRange = 1...50
    static let repsRange = 0...500

    init(id: UUID = UUID(), name: String = "", sets: Int = 3, reps: Int = 10, weightKg: Double? = nil) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weightKg = weightKg
        preserved = [:]
        originalName = name
    }

    private init?(stored: JSONValue) {
        guard case .object(var object) = stored, let name = object["exercise"]?.string else { return nil }
        self.id = UUID()
        self.name = name
        originalName = name
        sets = Self.int(object["sets"]) ?? 1
        reps = Self.int(object["reps"]) ?? 0
        if case .number(let weight)? = object["weightKg"] { weightKg = weight } else { weightKg = nil }
        for key in ["exercise", "sets", "reps", "weightKg", "order"] { object[key] = nil }
        preserved = object
    }

    var isNamed: Bool { !trimmedName.isEmpty }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The exercises of a stored `strengthPrescription`, in their order.
    static func exercises(in prescription: JSONValue?) -> [StrengthExerciseDraft] {
        guard let sets = prescription?["sets"]?.array else { return [] }
        let ordered = sets.enumerated().sorted { lhs, rhs in
            (int(lhs.element["order"]) ?? lhs.offset) < (int(rhs.element["order"]) ?? rhs.offset)
        }
        return ordered.compactMap { StrengthExerciseDraft(stored: $0.element) }
    }

    /// `{ version: 1, sets: [...] }`, the unnamed rows left out.
    static func prescription(_ exercises: [StrengthExerciseDraft]) -> JSONValue {
        let sets = exercises.filter(\.isNamed).enumerated().map { order, exercise in
            exercise.stored(order: order)
        }
        return .object(["version": .number(1), "sets": .array(sets)])
    }

    private func stored(order: Int) -> JSONValue {
        var object = preserved
        if trimmedName != originalName.trimmingCharacters(in: .whitespacesAndNewlines) {
            object["garmin"] = nil
            object["exerciseCatalogId"] = nil
        }
        object["exercise"] = .string(trimmedName)
        object["sets"] = .number(Double(sets))
        object["reps"] = .number(Double(reps))
        object["weightKg"] = weightKg.map(JSONValue.number) ?? .null
        object["order"] = .number(Double(order))
        return .object(object)
    }

    private static func int(_ value: JSONValue?) -> Int? {
        guard case .number(let number)? = value else { return nil }
        return Int(number)
    }

    /// Equal when the athlete would see the same row: identity and what the form edits.
    static func == (lhs: StrengthExerciseDraft, rhs: StrengthExerciseDraft) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.sets == rhs.sets
            && lhs.reps == rhs.reps && lhs.weightKg == rhs.weightKg
    }
}
