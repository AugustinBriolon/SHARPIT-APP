import Foundation

/// The body of a planned-session write: only the fields it names.
///
/// A key left out means "leave it" and `.null` means "clear it" — a distinction a `Codable`
/// struct of optionals cannot make, since it omits every nil, and an edit has to be able to
/// clear an hour or a title. Same shape as `AthleteProfilePatch`. The contract is the web's
/// `createPlannedSessionSchema` / `updatePlannedSessionSchema`.
nonisolated struct PlannedSessionFields: Encodable, Equatable, Sendable {
    private(set) var values: [String: JSONValue] = [:]

    init() {}

    var isEmpty: Bool { values.isEmpty }

    subscript(key: String) -> JSONValue? { values[key] }

    mutating func setType(_ type: V1ActivityType) {
        values["type"] = .string(type.rawValue)
    }

    /// The day, sent as its local noon — as the web's form does — so no time zone moves it
    /// to the day before or after (the server reads a bare `yyyy-MM-dd` as UTC midnight).
    mutating func setDay(_ day: Date, calendar: Calendar = .current) {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        values["date"] = .string(formatter.string(from: noon))
    }

    /// `HH:mm`, athlete-local; nil clears it.
    mutating func setStartTime(_ time: String?) {
        values["startTime"] = Self.text(time)
    }

    mutating func setTitle(_ title: String?) {
        values["title"] = Self.text(title)
    }

    /// The written déroulé of an endurance session.
    mutating func setDescription(_ description: String?) {
        values["description"] = Self.text(description)
    }

    mutating func setDurationMin(_ minutes: Int?) {
        values["durationMin"] = minutes.map { .number(Double($0)) } ?? .null
    }

    mutating func setIntensity(_ intensity: PlannedSessionIntensity?) {
        values["intensity"] = intensity.map { .string($0.rawValue) } ?? .null
    }

    mutating func setKey(_ isKey: Bool) {
        values["isKey"] = .bool(isKey)
    }

    mutating func setGoal(_ goalId: String?) {
        values["goalId"] = Self.text(goalId)
    }

    /// `{ version: 1, sets: [...] }` as `StrengthExerciseDraft.prescription` builds it.
    mutating func setStrengthPrescription(_ prescription: JSONValue?) {
        values["strengthPrescription"] = prescription ?? .null
    }

    /// The structured endurance steps. The app does not write them yet; it only clears
    /// them when the sport changes, since steps written for one sport mean nothing in another.
    mutating func clearEndurancePrescription() {
        values["endurancePrescription"] = .null
    }

    func encode(to encoder: Encoder) throws {
        try values.encode(to: encoder)
    }

    /// An empty or blank text is cleared rather than stored as "".
    private static func text(_ value: String?) -> JSONValue {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return .null
        }
        return .string(trimmed)
    }
}

/// `SessionIntensity` on the server, in the words the web and the coach's proposals use.
nonisolated enum PlannedSessionIntensity: String, CaseIterable, Identifiable, Sendable {
    case recovery = "RECOVERY"
    case endurance = "ENDURANCE"
    case tempo = "TEMPO"
    case threshold = "THRESHOLD"
    case vo2max = "VO2MAX"
    case race = "RACE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recovery: "Récupération"
        case .endurance: "Endurance"
        case .tempo: "Tempo"
        case .threshold: "Seuil"
        case .vo2max: "VO2max"
        case .race: "Compétition"
        }
    }
}
