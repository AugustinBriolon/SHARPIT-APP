import Foundation

/// A trip or a constraint just saved, and whether the plan should be adjusted for it: only when
/// it narrows the training, falls within the adapter's two weeks and lands on a session still to
/// do. Then « Ajuster le planning » opens with the trip already said, as « Rattraper ma semaine »
/// does for a miss; the coach proposes, the athlete keeps what they want.
struct PlanTripAdaptation: Sendable {
    let saved: CreateCoachMemoryInput

    /// Nil when nothing in the plan needs a second look.
    static func offer(
        for saved: CreateCoachMemoryInput,
        sessions: [V1PlannedSessionItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PlanTripAdaptation? {
        guard narrowsTraining(saved) else { return nil }
        let days = dayRange(of: saved, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: PlanAdjustmentStore.horizonDays, to: today),
              days.upperBound >= today, days.lowerBound <= horizon else { return nil }
        let touched = sessions.contains { session in
            session.completed != true && days.contains(calendar.startOfDay(for: session.date))
        }
        return touched ? PlanTripAdaptation(saved: saved) : nil
    }

    /// The days to read the plan over, local midnights.
    static func dayRange(of saved: CreateCoachMemoryInput, calendar: Calendar = .current) -> ClosedRange<Date> {
        let start = calendar.startOfDay(for: saved.startDate)
        return start...max(start, calendar.startOfDay(for: saved.endDate))
    }

    /// What the coach is told the athlete asks for.
    func focus(calendar: Calendar = .current) -> String {
        let days = Self.dayRange(of: saved, calendar: calendar)
        let style = Date.FormatStyle(locale: AppLanguage.locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide)
        let start = days.lowerBound.formatted(style)
        let when = days.lowerBound == days.upperBound
            ? String(localized: "le \(start)")
            : String(localized: "du \(start) au \(days.upperBound.formatted(style))")
        let what = saved.type == .travel
            ? String(localized: "Je suis en déplacement à \(saved.locationLabel ?? "") \(when)")
            : String(localized: "J'ai une contrainte « \(saved.label ?? "") » \(when)")
        let training = TripTraining(
            constraint: saved.trainingConstraint ?? .full,
            allowedDisciplines: saved.allowedDisciplines
        ).outcome
        return "\(what) : \(training) "
            + String(localized: "Adapte les séances concernées et la suite si besoin, en gardant les séances clés.")
    }

    /// A trip that changes nothing about training (all sports, usual load) leaves the plan alone.
    private static func narrowsTraining(_ saved: CreateCoachMemoryInput) -> Bool {
        guard saved.type == .travel || saved.type == .constraint else { return false }
        if (saved.trainingConstraint ?? .full) != .full { return true }
        return !(saved.allowedDisciplines ?? []).isEmpty
    }
}
