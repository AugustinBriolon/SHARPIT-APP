import Foundation

/// What the training mode reads as, apart from its drawing: the status pill it takes, what it
/// changes for the plan and the coach, how long it holds. Pure, so the copy and the date maths are
/// pinned by tests (`ActivityStatusReadoutTests`).
extension ActivityStatusId {
    /// The Clinique status the mode is told by. Ink runs the interface, so a hue only appears on a
    /// pill with a word: a pause is unknown (nothing wrong), a sickness is to watch, an injury alerts.
    var clinique: CliniqueStatus {
        switch self {
        case .active: .good
        case .paused: .unknown
        case .sick: .watch
        case .injured: .alert
        }
    }

    /// The wash the mode's drawer takes at its top, in the same reading as its pill.
    var wash: CliniqueWash {
        switch self {
        case .active: .good
        case .paused: .neutral
        case .sick: .watch
        case .injured: .alert
        }
    }

    /// What the mode changes, one line for the plan and one for the coach, in the web's meaning
    /// (`planningImpact`). Nothing is promised that the server does not do.
    var effects: [ActivityStatusEffect] {
        switch self {
        case .active:
            []
        case .paused:
            [
                ActivityStatusEffect(symbol: "calendar", text: String(localized: "Le plan est en veille jusqu'à la reprise.")),
                ActivityStatusEffect(symbol: "bubble.left", text: String(localized: "Le coach ne propose aucune charge volontaire.")),
            ]
        case .injured:
            [
                ActivityStatusEffect(symbol: "calendar", text: String(localized: "Les séances à risque sont adaptées ou reportées.")),
                ActivityStatusEffect(symbol: "bubble.left", text: String(localized: "La sécurité passe avant la charge.")),
            ]
        case .sick:
            [
                ActivityStatusEffect(symbol: "calendar", text: String(localized: "Le repos passe avant la charge.")),
                ActivityStatusEffect(symbol: "bubble.left", text: String(localized: "Reprise seulement quand le corps suit.")),
            ]
        }
    }
}

nonisolated struct ActivityStatusEffect: Equatable, Sendable, Identifiable {
    let symbol: String
    let text: String
    var id: String { symbol + text }
}

/// How long a mode holds, as the athlete picks it. The wire only knows « until modified » and
/// « until a day »; the presets are three ways to name a day.
nonisolated enum ActivityStatusDuration: Hashable, Sendable, CaseIterable {
    case untilModified
    case days3
    case week1
    case weeks2
    case date

    var label: String {
        switch self {
        case .untilModified: String(localized: "Jusqu'à nouvel ordre")
        case .days3: String(localized: "3 jours")
        case .week1: String(localized: "1 semaine")
        case .weeks2: String(localized: "2 semaines")
        case .date: String(localized: "Une date")
        }
    }

    /// Days from today the preset ends on; `nil` where it names none.
    var days: Int? {
        switch self {
        case .days3: 3
        case .week1: 7
        case .weeks2: 14
        case .untilModified, .date: nil
        }
    }

    /// The retention a preset writes. `date` keeps the day the picker holds.
    func retention(picked: Date, now: Date = .now, calendar: Calendar = .current) -> ActivityStatusRetention {
        switch self {
        case .untilModified:
            return .untilModified
        case .date:
            return .untilDate(ActivityStatusDate.string(from: picked, calendar: calendar))
        case .days3, .week1, .weeks2:
            let end = calendar.date(byAdding: .day, value: days ?? 0, to: now) ?? now
            return .untilDate(ActivityStatusDate.string(from: end, calendar: calendar))
        }
    }

    /// Which chip a stored retention lights: a day that is exactly 3, 7 or 14 days out is the
    /// preset, any other day is « Une date ». A preset read back a day later is still « Une date »,
    /// which is what it has become.
    static func matching(_ retention: ActivityStatusRetention, now: Date = .now, calendar: Calendar = .current) -> ActivityStatusDuration {
        guard let day = retention.untilDate, let end = ActivityStatusDate.date(from: day, calendar: calendar) else {
            return .untilModified
        }
        let today = calendar.startOfDay(for: now)
        let gap = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: end)).day
        return allCases.first { $0.days != nil && $0.days == gap } ?? .date
    }
}

/// The line that says when the mode ends.
nonisolated enum ActivityStatusReadout {
    /// « Reprise demain », « Reprise dans 9 jours »; nothing for a mode held until changed, and
    /// « Reprise aujourd'hui » on the last day, since the server only lets a past day go.
    static func resumption(_ retention: ActivityStatusRetention, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let day = retention.untilDate, let end = ActivityStatusDate.date(from: day, calendar: calendar) else { return nil }
        let gap = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)
        ).day ?? 0
        switch gap {
        case ..<1: return String(localized: "Reprise aujourd'hui")
        case 1: return String(localized: "Reprise demain")
        default: return String(localized: "Reprise dans \(gap) jours")
        }
    }

    /// The day itself, « 3 déc. », for the line under the countdown.
    static func endDay(_ retention: ActivityStatusRetention, calendar: Calendar = .current) -> Date? {
        guard let day = retention.untilDate else { return nil }
        return ActivityStatusDate.date(from: day, calendar: calendar)
    }
}
