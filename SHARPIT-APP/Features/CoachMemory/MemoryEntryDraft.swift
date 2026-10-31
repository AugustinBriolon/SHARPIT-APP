import Foundation

/// A sport the athlete can keep up during a dated period (the server's `TravelDiscipline`).
nonisolated enum AllowedDiscipline: String, CaseIterable, Identifiable, Hashable, Sendable {
    case run = "RUN"
    case bike = "BIKE"
    case swim = "SWIM"
    case strength = "STRENGTH"
    case mobility = "MOBILITY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: String(localized: "Course")
        case .bike: String(localized: "Vélo")
        case .swim: String(localized: "Natation")
        case .strength: String(localized: "Muscu")
        case .mobility: String(localized: "Mobilité")
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .bike: "bicycle"
        case .swim: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .mobility: "figure.yoga"
        }
    }

    var isEndurance: Bool { self == .run || self == .bike || self == .swim }
}

/// What the athlete can do over a period, in the only combinations the server honours.
///
/// `resolveTrainingFields` derives the constraint from the sports as soon as any are sent, so
/// « allégé » with a list of sports would silently be stored as normal training. Lighter
/// therefore carries no list, and the sentence under the choice says what will really happen.
nonisolated struct TripTraining: Equatable, Sendable {
    enum Mode: Hashable, CaseIterable, Sendable {
        case normal, lighter, pause

        var label: String {
            switch self {
            case .normal: TravelTrainingConstraint.full.badgeText
            case .lighter: TravelTrainingConstraint.reduced.badgeText
            case .pause: TravelTrainingConstraint.none.badgeText
            }
        }
    }

    var mode: Mode = .normal
    var sports = Set(AllowedDiscipline.allCases)

    init() {}

    init(constraint: TravelTrainingConstraint, allowedDisciplines: [String]?) {
        let listed = Set((allowedDisciplines ?? []).compactMap(AllowedDiscipline.init(rawValue:)))
        switch constraint {
        case .none:
            mode = .pause
        case .reduced where listed.isEmpty:
            mode = .lighter
        case .mobilityOnly where listed.isEmpty:
            sports = [.mobility]
        default:
            if !listed.isEmpty { sports = listed }
        }
    }

    var isComplete: Bool { mode != .normal || !sports.isEmpty }

    /// Mirrors `deriveTravelTrainingConstraint`, so a row reads right before the reload.
    var constraint: TravelTrainingConstraint {
        switch mode {
        case .pause: .none
        case .lighter: .reduced
        case .normal:
            if sports == [.mobility] { .mobilityOnly }
            else if sports.contains(where: \.isEndurance) || sports.isEmpty { .full }
            else { .reduced }
        }
    }

    /// Nil when nothing narrows the sports: all five mean the same as no list.
    var allowedDisciplines: [String]? {
        guard mode == .normal, sports.count < AllowedDiscipline.allCases.count, !sports.isEmpty else { return nil }
        return orderedSports.map(\.rawValue)
    }

    var outcome: String {
        switch mode {
        case .pause:
            return String(localized: "Le coach ne prévoit aucune séance sur ces dates.")
        case .lighter:
            return String(localized: "Tous tes sports, volume et intensité réduits.")
        case .normal:
            if sports.isEmpty { return String(localized: "Choisis au moins un sport.") }
            if allowedDisciplines == nil { return String(localized: "Le plan continue sans changement.") }
            let names = orderedSports.map(\.label).formatted(.list(type: .and).locale(AppLanguage.locale))
            switch constraint {
            case .full: return String(localized: "\(names) seulement, à ta charge habituelle.")
            case .mobilityOnly: return String(localized: "Mobilité seulement, charge très réduite.")
            default: return String(localized: "\(names) seulement, charge réduite.")
            }
        }
    }

    private var orderedSports: [AllowedDiscipline] {
        AllowedDiscipline.allCases.filter(sports.contains)
    }
}

/// The form's answers, and the single place they become what the server accepts.
nonisolated struct MemoryEntryDraft: Equatable, Sendable {
    var type: CoachMemoryType
    var title = ""
    var location = ""
    var startDay: Date
    var endDay: Date
    var note = ""
    var training = TripTraining()

    private var originalLocation: String?

    init(type: CoachMemoryType, today: Date = Date(), calendar: Calendar = .current) {
        self.type = type
        startDay = today
        endDay = calendar.date(byAdding: .day, value: 3, to: today) ?? today
    }

    init(entry: CoachMemoryEntry, calendar: Calendar = .current) {
        type = entry.type
        title = entry.label ?? ""
        location = entry.locationLabel ?? ""
        originalLocation = entry.locationLabel
        startDay = Self.localDay(fromServerDay: entry.startDate, calendar: calendar)
        endDay = Self.localDay(fromServerDay: entry.endDate, calendar: calendar)
        note = entry.note ?? ""
        training = TripTraining(constraint: entry.trainingConstraint, allowedDisciplines: entry.allowedDisciplines)
    }

    var hasDates: Bool { !type.isOpenEnded }
    var hasTraining: Bool { !type.isOpenEnded }

    /// The server asks a trip for a place of two characters at least, and a fin after the début.
    var isComplete: Bool {
        if type == .travel {
            guard trimmed(location).count >= 2 else { return false }
        } else if trimmed(title).isEmpty {
            return false
        }
        if hasDates, Self.dayKey(endDay) < Self.dayKey(startDay) { return false }
        return !hasTraining || training.isComplete
    }

    func input(calendar: Calendar = .current) -> CreateCoachMemoryInput {
        CreateCoachMemoryInput(
            type: type,
            label: type == .travel ? tripLabel : trimmed(title).nilIfEmpty,
            locationLabel: type == .travel ? trimmed(location) : nil,
            startDate: Self.noon(of: startDay, calendar: calendar),
            endDate: hasDates
                ? Self.noon(of: endDay, calendar: calendar)
                : calendar.date(from: DateComponents(year: 2099, month: 12, day: 31, hour: 12)) ?? endDay,
            note: trimmed(note).nilIfEmpty,
            trainingConstraint: hasTraining ? training.constraint : .full,
            allowedDisciplines: hasTraining ? training.allowedDisciplines : nil
        )
    }

    /// The form asks a trip for its place only. A title the coach gave it stays, unless the
    /// place changed under it: it would name somewhere the athlete no longer goes.
    private var tripLabel: String? {
        originalLocation == trimmed(location) ? trimmed(title).nilIfEmpty : nil
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The day as the athlete picked it: the server keeps the date of the instant in UTC, and
    /// local noon falls on the same date there, as a planned session's day does.
    private static func noon(of day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private static func localDay(fromServerDay day: Date, calendar: Calendar) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = utc.dateComponents([.year, .month, .day], from: day)
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12)) ?? day
    }

    private static func dayKey(_ date: Date) -> Int {
        PlanTravel.dayKey(date, in: .current)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
