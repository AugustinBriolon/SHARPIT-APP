import Foundation

/// What the goal form edits, for a new goal and an existing one alike.
///
/// An edit sends only what changed (`changes(from:)`): a key left out leaves the field, `null`
/// clears it — the web's `updateGoalSchema` is a partial of the creation schema, so a field the
/// form does not show (the metric key, the start value, the horizon) is never touched.
nonisolated struct GoalDraft: Equatable, Sendable {
    var kind: GoalKind = .race
    var title = ""
    var priority: GoalPriority = .a
    var hasTargetDate = true
    var targetDate: Date
    var location = ""
    var raceFormat = ""
    var targetPerformance = ""
    var targetValueText = ""
    var currentValueText = ""
    var unit = ""
    var notes = ""

    /// A new goal: a race three months out, the athlete's main one.
    static func new(now: Date = .now, calendar: Calendar = .current) -> GoalDraft {
        GoalDraft(targetDate: calendar.date(byAdding: .month, value: 3, to: now) ?? now)
    }

    init(targetDate: Date) {
        self.targetDate = targetDate
    }

    init(goal: V1Goal, now: Date = .now) {
        kind = goal.kind
        title = goal.title
        priority = goal.priority ?? .a
        hasTargetDate = goal.targetDate != nil
        targetDate = goal.targetDate ?? now
        location = goal.location ?? ""
        raceFormat = goal.raceFormat ?? ""
        targetPerformance = goal.targetPerformance ?? ""
        targetValueText = goal.targetValue.map(Self.number) ?? ""
        currentValueText = goal.currentValue.map(Self.number) ?? ""
        unit = goal.unit ?? ""
        notes = goal.notes ?? ""
    }

    /// A race always has its day (the server refuses one without); a figure may have none.
    var datesTarget: Bool { kind == .race || hasTargetDate }

    /// What keeps the form from being sent, worded for the athlete; nil when it can go.
    var missingRequirement: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Donne un nom à ton objectif." }
        if !targetValueText.isEmpty, Self.parse(targetValueText) == nil { return "La valeur cible n’est pas un nombre." }
        if !currentValueText.isEmpty, Self.parse(currentValueText) == nil { return "La valeur actuelle n’est pas un nombre." }
        return nil
    }

    var creation: CreateGoalInput {
        CreateGoalInput(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            priority: kind == .race ? priority : nil,
            targetDate: datesTarget ? Self.noon(of: targetDate) : nil,
            location: kind == .race ? Self.text(location) : nil,
            raceFormat: kind == .race ? Self.text(raceFormat) : nil,
            targetPerformance: kind == .race ? Self.text(targetPerformance) : nil,
            targetValue: kind == .metric ? Self.parse(targetValueText) : nil,
            startValue: nil,
            currentValue: kind == .metric ? Self.parse(currentValueText) : nil,
            unit: kind == .metric ? Self.text(unit) : nil,
            notes: Self.text(notes)
        )
    }

    /// The fields that differ from `original`, as the PATCH body.
    func changes(from original: GoalDraft, calendar: Calendar = .current) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        if title != original.title { fields["title"] = .string(title.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if kind != original.kind { fields["kind"] = .string(kind.rawValue) }
        if kind == .race, priority != original.priority || kind != original.kind {
            fields["priority"] = .string(priority.rawValue)
        }
        let dayChanged = datesTarget != original.datesTarget
            || (datesTarget && !calendar.isDate(targetDate, inSameDayAs: original.targetDate))
        if dayChanged {
            fields["targetDate"] = datesTarget ? .string(Self.noon(of: targetDate, calendar: calendar).toAPI) : .null
        }
        if location != original.location { fields["location"] = Self.json(location) }
        if raceFormat != original.raceFormat { fields["raceFormat"] = Self.json(raceFormat) }
        if targetPerformance != original.targetPerformance { fields["targetPerformance"] = Self.json(targetPerformance) }
        if targetValueText != original.targetValueText { fields["targetValue"] = Self.parse(targetValueText).map(JSONValue.number) ?? .null }
        if currentValueText != original.currentValueText { fields["currentValue"] = Self.parse(currentValueText).map(JSONValue.number) ?? .null }
        if unit != original.unit { fields["unit"] = Self.json(unit) }
        if notes != original.notes { fields["notes"] = Self.json(notes) }
        return fields
    }

    /// Accepts the French decimal comma.
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func number(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(value).replacingOccurrences(of: ".", with: ",")
    }

    /// The day as its local noon, so no time zone moves a race to the day before.
    private static func noon(of day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private static func text(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func json(_ value: String) -> JSONValue {
        text(value).map(JSONValue.string) ?? .null
    }
}

extension V1Goal {
    /// The goal as the athlete just edited it, shown before the server answers.
    nonisolated func applying(_ draft: GoalDraft) -> V1Goal {
        var goal = self
        let created = draft.creation
        goal.title = created.title
        goal.kind = draft.kind
        if draft.kind == .race { goal.priority = draft.priority }
        goal.targetDate = created.targetDate
        if draft.kind == .race {
            goal.location = created.location
            goal.raceFormat = created.raceFormat
            goal.targetPerformance = created.targetPerformance
        } else {
            goal.targetValue = created.targetValue
            goal.currentValue = created.currentValue
            goal.unit = created.unit
        }
        goal.notes = created.notes
        return goal
    }
}
