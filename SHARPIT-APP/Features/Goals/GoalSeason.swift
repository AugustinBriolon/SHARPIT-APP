import Foundation

/// The season around the principal race: one principal per six months, the races before it as
/// its steps. Pure, so the form, the list and the tests read the same rules.
nonisolated enum GoalSeason {
    /// Two principal races closer than this compete for the same taper.
    static let windowMonths = 6

    /// The principal ahead, then the races before it, soonest first, each with the days to
    /// the next node (the following step, or the principal).
    struct Timeline: Equatable, Sendable {
        let principal: V1Goal
        let steps: [Step]
    }

    struct Step: Equatable, Sendable, Identifiable {
        let goal: V1Goal
        let daysToNext: Int
        var id: String { goal.id }
    }

    /// Two principals in one season, and the one to pass as a step (the shorter, else the sooner).
    struct Conflict: Equatable, Sendable, Identifiable {
        let kept: V1Goal
        let demoted: V1Goal
        var id: String { [kept.id, demoted.id].sorted().joined(separator: "|") }
    }

    // MARK: - Form

    /// The role a new race starts on: principal when the season has none and it is the longest
    /// race in it (the farthest on a tie), a step otherwise.
    static func suggestedPriority(
        date: Date,
        format: String,
        among goals: [V1Goal],
        excluding id: String? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalPriority {
        let season = racesAround(date, in: goals, excluding: id, now: now, calendar: calendar)
        if season.contains(where: { $0.role == .primary }) { return .b }
        let longer = season.contains { outranks(($0.raceFormat, $0.targetDate ?? date), (format, date)) }
        return longer ? .b : .a
    }

    /// The other principal race within six months of `date`, the nearest first; nil when none.
    static func principalConflict(
        date: Date,
        among goals: [V1Goal],
        excluding id: String? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> V1Goal? {
        racesAround(date, in: goals, excluding: id, now: now, calendar: calendar)
            .filter { $0.role == .primary }
            .min { abs(($0.targetDate ?? date).timeIntervalSince(date)) < abs(($1.targetDate ?? date).timeIntervalSince(date)) }
    }

    // MARK: - Objectifs

    /// The nearest principal race ahead and the races leading to it; nil without a principal.
    static func timeline(in goals: [V1Goal], now: Date = .now, calendar: Calendar = .current) -> Timeline? {
        let ahead = upcoming(goals, now: now, calendar: calendar)
        guard let principal = ahead.first(where: { $0.role == .primary }), let end = principal.targetDate else { return nil }
        let before = ahead.filter { ($0.targetDate ?? end) < end && $0.role != .primary }
        let steps = before.enumerated().map { index, goal in
            let next = index + 1 < before.count ? before[index + 1].targetDate ?? end : end
            return Step(goal: goal, daysToNext: days(from: goal.targetDate ?? end, to: next, calendar: calendar))
        }
        return Timeline(principal: principal, steps: steps)
    }

    /// Every pair of principals ahead that share a season, once each. The server's
    /// `seasonConflict` when it sends the roles, else the same rule read here.
    static func conflicts(in goals: [V1Goal], now: Date = .now, calendar: Calendar = .current) -> [Conflict] {
        var seen = Set<String>()
        return upcoming(goals, now: now, calendar: calendar)
            .filter { $0.role == .primary }
            .compactMap { goal -> Conflict? in
                guard let other = conflictingPrincipal(of: goal, in: goals, now: now, calendar: calendar) else { return nil }
                let conflict = pair(goal, other)
                return seen.insert(conflict.id).inserted ? conflict : nil
            }
    }

    // MARK: - Reading

    /// « dans 5 mois », « dans 3 semaines », « dans 4 jours ».
    static func until(days: Int) -> String {
        days <= 0 ? "aujourd’hui" : "dans \(span(days: days))"
    }

    /// « 5 mois », « 3 semaines », « 4 jours ».
    static func span(days: Int) -> String {
        if days >= 60 {
            let months = Int((Double(days) / 30.44).rounded())
            return "\(months) mois"
        }
        if days >= 14 { return "\(Int((Double(days) / 7).rounded())) semaines" }
        return days == 1 ? "1 jour" : "\(days) jours"
    }

    /// How long a format is, for « the longest race » only: an order, never a distance.
    // shortcut: keywords only (Ironman, XXL, 70.3, marathon…); read a parsed distance if the server ever sends one.
    static func formatRank(_ format: String?) -> Int {
        let text = (format ?? "").lowercased()
        let words = Set(text.split { !$0.isLetter && !$0.isNumber && $0 != "." }.map(String.init))
        if words.contains("xxl") || words.contains("140.6") || (text.contains("ironman") && !isHalf(text)) { return 100 }
        if words.contains("xl") { return 80 }
        if isHalf(text) || words.contains("l") { return 60 }
        if text.contains("marathon") && !text.contains("semi") { return 50 }
        if words.contains("m") || text.contains("olympi") { return 30 }
        if text.contains("semi") { return 25 }
        if words.contains("s") || words.contains("xs") || text.contains("sprint") { return 10 }
        return 0
    }

    // MARK: - Private

    private static func isHalf(_ text: String) -> Bool {
        text.contains("70.3") || text.contains("half") || text.contains("demi")
    }

    /// Longer wins; on the same length, the later race.
    private static func outranks(_ lhs: (String?, Date), _ rhs: (String?, Date)) -> Bool {
        let (l, r) = (formatRank(lhs.0), formatRank(rhs.0))
        return l != r ? l > r : lhs.1 > rhs.1
    }

    private static func pair(_ a: V1Goal, _ b: V1Goal) -> Conflict {
        let aFirst = outranks((a.raceFormat, a.targetDate ?? .distantPast), (b.raceFormat, b.targetDate ?? .distantPast))
        return aFirst ? Conflict(kept: a, demoted: b) : Conflict(kept: b, demoted: a)
    }

    private static func conflictingPrincipal(of goal: V1Goal, in goals: [V1Goal], now: Date, calendar: Calendar) -> V1Goal? {
        if goal.priorityRole != nil {
            guard let other = goal.seasonConflict.flatMap({ c in goals.first { $0.id == c.otherGoalId } }),
                  other.role == .primary, !other.isReached else { return nil }
            return other
        }
        guard let date = goal.targetDate else { return nil }
        return principalConflict(date: date, among: goals, excluding: goal.id, now: now, calendar: calendar)
    }

    private static func upcoming(_ goals: [V1Goal], now: Date, calendar: Calendar) -> [V1Goal] {
        let today = calendar.startOfDay(for: now)
        return goals
            .filter { $0.kind == .race && !$0.isReached && ($0.targetDate.map { calendar.startOfDay(for: $0) >= today } ?? false) }
            .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    private static func racesAround(_ date: Date, in goals: [V1Goal], excluding id: String?, now: Date, calendar: Calendar) -> [V1Goal] {
        guard let from = calendar.date(byAdding: .month, value: -windowMonths, to: date),
              let to = calendar.date(byAdding: .month, value: windowMonths, to: date) else { return [] }
        return upcoming(goals, now: now, calendar: calendar).filter { goal in
            guard goal.id != id, let day = goal.targetDate else { return false }
            return day >= from && day <= to
        }
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}
