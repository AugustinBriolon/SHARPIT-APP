import Foundation

/// What a day of the plan actually holds.
///
/// A past day is rarely a plan — it is what happened. When an activity was recorded
/// against a planned session, the activity absorbs it: the plan shows the session that
/// was *done*, with the execution score, and the original prescription stays reachable
/// from the activity's own screen. Three cases, and no fourth:
///
/// - `executed` — an activity, whether or not it came from the plan
/// - `planned` — a prescription still ahead
/// - `missed` — a prescription whose day has passed with nothing recorded against it
enum PlanEntry: Identifiable, Hashable {
    case executed(PlanExecutedEntry)
    case planned(V1PlannedSessionItem)
    case missed(V1PlannedSessionItem)

    var id: String {
        switch self {
        case .executed(let entry): "executed-\(entry.activity.id)"
        case .planned(let session): "planned-\(session.id)"
        case .missed(let session): "missed-\(session.id)"
        }
    }

    var date: Date {
        switch self {
        case .executed(let entry): entry.activity.date
        case .planned(let session), .missed(let session): session.date
        }
    }
}

struct PlanExecutedEntry: Hashable {
    let activity: V1ActivityListItem
    /// The prescription this activity was recorded against, when there was one.
    let plannedTitle: String?
    /// 0…100. Present only when the session was analysed against its plan.
    let complianceScore: Double?

    var wasPlanned: Bool { plannedTitle != nil || complianceScore != nil }
}

enum PlanEntryBuilder {
    /// Merges what was prescribed with what was done, for one day.
    ///
    /// An activity linked to a planned session replaces it rather than sitting beside it:
    /// showing both would claim the athlete owed two sessions when they owed one.
    static func entries(
        planned: [V1PlannedSessionItem],
        activities: [V1ActivityListItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlanEntry] {
        let absorbed = Set(activities.compactMap { $0.plannedSession?.id })
        let startOfToday = calendar.startOfDay(for: now)

        let executed = activities.map { activity in
            PlanEntry.executed(
                PlanExecutedEntry(
                    activity: activity,
                    plannedTitle: activity.plannedSession?.title,
                    complianceScore: activity.plannedSession?.analysis?.complianceScore
                )
            )
        }

        let remaining = planned
            .filter { !absorbed.contains($0.id) }
            .map { session in
                calendar.startOfDay(for: session.date) < startOfToday
                    ? PlanEntry.missed(session)
                    : PlanEntry.planned(session)
            }

        return (executed + remaining).sorted { $0.date < $1.date }
    }
}

/// What one day of the week strip says at a glance.
///
/// The strip is an index, not a second copy of the list: it answers "which days did I
/// train, which are still ahead, which did I miss" and nothing more. The precedence is
/// deliberate — a day where something was done reads as done, even if a second
/// prescription that day went unanswered, because the row below carries that detail.
enum PlanDayStatus: Equatable, Sendable {
    case executed
    case planned
    case missed

    static func status(of entries: [PlanEntry]) -> PlanDayStatus? {
        if entries.contains(where: { if case .executed = $0 { true } else { false } }) {
            return .executed
        }
        if entries.contains(where: { if case .planned = $0 { true } else { false } }) {
            return .planned
        }
        if entries.contains(where: { if case .missed = $0 { true } else { false } }) {
            return .missed
        }
        return nil
    }
}
