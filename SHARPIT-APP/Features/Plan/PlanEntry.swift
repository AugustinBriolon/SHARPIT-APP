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
///
/// A brick — legs chained without a break — is one prescription, so it is one entry: listed
/// leg by leg it read as two sessions to do apart, which is exactly what a brick is not. Done,
/// it stays one entry (`doneBrick`): two activities side by side read as two separate outings.
enum PlanEntry: Identifiable, Hashable {
    case executed(PlanExecutedEntry)
    case planned(V1PlannedSessionItem)
    case missed(V1PlannedSessionItem)
    case brick(PlanBrick)
    case doneBrick(PlanDoneBrick)

    var id: String {
        switch self {
        case .executed(let entry): "executed-\(entry.activity.id)"
        case .planned(let session): "planned-\(session.id)"
        case .missed(let session): "missed-\(session.id)"
        case .brick(let brick): "brick-\(brick.id)"
        case .doneBrick(let brick): "done-brick-\(brick.id)"
        }
    }

    var date: Date {
        switch self {
        case .executed(let entry): entry.activity.date
        case .planned(let session), .missed(let session): session.date
        case .brick(let brick): brick.date
        case .doneBrick(let brick): brick.date
        }
    }

    /// What tapping the entry opens, when it opens a drawer rather than an activity's screen.
    var selection: PlanSelection? {
        switch self {
        case .executed: nil
        case .planned(let session), .missed(let session): .session(session)
        case .brick(let brick): .brick(brick)
        case .doneBrick(let brick): .doneBrick(brick)
        }
    }
}

/// A brick: legs chained without a break, read and opened as one session.
struct PlanBrick: Hashable, Identifiable {
    /// The legs' shared `brickGroupId`.
    let id: String
    /// In the order they are done; two at least — one leg left is a plain session.
    let legs: [V1PlannedSessionItem]
    /// Its day passed with nothing recorded against it.
    let isMissed: Bool

    var date: Date { legs[0].date }

    /// « Vélo → Course »: the chain is what the brick trains.
    var chain: String { legs.map(\.displayType).joined(separator: " → ") }

    var totalDurationMin: Int? {
        let durations = legs.compactMap(\.durationMin)
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }

    var totalLoad: Double? {
        let loads = legs.compactMap(\.load).filter { $0 > 0 }
        return loads.isEmpty ? nil : loads.reduce(0, +)
    }

    var isOnWatch: Bool { legs.contains { $0.garminWorkoutId != nil } }

    func contains(sessionId: String) -> Bool { legs.contains { $0.id == sessionId } }
}

/// A brick done: its legs in order, each beside the activity that realized it.
struct PlanDoneBrick: Hashable, Identifiable {
    struct Leg: Hashable {
        let session: V1PlannedSessionItem
        /// Nil for a leg left undone while the others were recorded.
        let activity: V1ActivityListItem?
    }

    /// The legs' shared `brickGroupId`.
    let id: String
    /// In the order they were prescribed; two done at least.
    let legs: [Leg]

    /// When the first recorded leg started.
    var date: Date { legs.compactMap(\.activity?.date).min() ?? legs[0].session.date }

    var sports: [String] { legs.map { $0.activity?.type.label ?? $0.session.displayType } }

    var chain: String { sports.joined(separator: " → ") }

    var symbolNames: [String] { legs.map { $0.activity?.type.symbolName ?? $0.session.symbolName } }

    /// What was recorded, in minutes; nil when no leg carries a duration.
    var totalDurationMin: Int? {
        let seconds = legs.compactMap(\.activity?.duration)
        return seconds.isEmpty ? nil : Int((seconds.reduce(0, +) / 60).rounded())
    }

    func contains(sessionId: String) -> Bool { legs.contains { $0.session.id == sessionId } }
}

/// What a tap in Plan opens as a drawer: one session, a brick as a whole, or a brick done.
enum PlanSelection: Identifiable, Hashable {
    case session(V1PlannedSessionItem)
    case brick(PlanBrick)
    case doneBrick(PlanDoneBrick)

    var id: String {
        switch self {
        case .session(let session): "session-\(session.id)"
        case .brick(let brick): "brick-\(brick.id)"
        case .doneBrick(let brick): "done-brick-\(brick.id)"
        }
    }

    var date: Date {
        switch self {
        case .session(let session): session.date
        case .brick(let brick): brick.date
        case .doneBrick(let brick): brick.date
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
        var absorbed = Set(activities.compactMap { $0.plannedSession?.id })
        for session in planned {
            if session.activityId != nil || session.completed == true {
                absorbed.insert(session.id)
            }
        }
        let startOfToday = calendar.startOfDay(for: now)
        let realizedBricks = doneBricks(planned: planned, activities: activities)
        let inDoneBrick = Set(realizedBricks.flatMap { brick in brick.legs.compactMap(\.activity?.id) })
        let legsInDoneBrick = Set(realizedBricks.flatMap { brick in brick.legs.map(\.session.id) })

        let executed = activities.filter { !inDoneBrick.contains($0.id) }.map { activity in
            let matchingPlanned = planned.first { session in session.realizes(activity) }
            let title = activity.plannedSession?.title ?? matchingPlanned?.title ?? (matchingPlanned != nil ? matchingPlanned?.displayType : nil)
            let score = activity.plannedSession?.analysis?.complianceScore

            return PlanEntry.executed(
                PlanExecutedEntry(
                    activity: activity,
                    plannedTitle: title,
                    complianceScore: score
                )
            )
        }

        let remaining = prescriptions(
            planned.filter { !absorbed.contains($0.id) && !legsInDoneBrick.contains($0.id) },
            isPast: { calendar.startOfDay(for: $0) < startOfToday }
        )

        return (executed + realizedBricks.map(PlanEntry.doneBrick) + remaining).sorted { $0.date < $1.date }
    }

    /// The bricks two activities or more realized, each gathered with every one of its legs —
    /// one left undone shows inside the brick rather than beside it.
    private static func doneBricks(
        planned: [V1PlannedSessionItem],
        activities: [V1ActivityListItem]
    ) -> [PlanDoneBrick] {
        let legsByBrick = Dictionary(grouping: planned.filter { $0.brickGroupId != nil }) { $0.brickGroupId! }
        return legsByBrick.compactMap { brickId, sessions in
            let legs = sessions
                .sorted { ($0.brickOrder ?? 0) < ($1.brickOrder ?? 0) }
                .map { session in
                    PlanDoneBrick.Leg(session: session, activity: activities.first { session.realizes($0) })
                }
            guard legs.compactMap(\.activity).count > 1 else { return nil }
            return PlanDoneBrick(id: brickId, legs: legs)
        }
        .sorted { $0.date < $1.date }
    }

    /// The sessions still owed, a brick's legs gathered into one entry. A brick with one leg
    /// left — the other done or deleted — is a plain session, as the web demotes it.
    private static func prescriptions(
        _ sessions: [V1PlannedSessionItem],
        isPast: (Date) -> Bool
    ) -> [PlanEntry] {
        let legsByBrick = Dictionary(grouping: sessions.filter { $0.brickGroupId != nil }) { $0.brickGroupId! }
        var gathered = Set<String>()
        return sessions.compactMap { session in
            if let brickId = session.brickGroupId, let legs = legsByBrick[brickId], legs.count > 1 {
                guard gathered.insert(brickId).inserted else { return nil }
                let ordered = legs.sorted { ($0.brickOrder ?? 0) < ($1.brickOrder ?? 0) }
                return .brick(PlanBrick(id: brickId, legs: ordered, isMissed: isPast(ordered[0].date)))
            }
            return isPast(session.date) ? .missed(session) : .planned(session)
        }
    }
}

private extension V1PlannedSessionItem {
    /// The session was recorded as this activity — linked from either side.
    func realizes(_ activity: V1ActivityListItem) -> Bool {
        activityId == activity.id || id == activity.plannedSession?.id
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
        if entries.contains(where: {
            switch $0 {
            case .executed, .doneBrick: true
            default: false
            }
        }) {
            return .executed
        }
        if entries.contains(where: {
            switch $0 {
            case .planned: true
            case .brick(let brick): !brick.isMissed
            default: false
            }
        }) {
            return .planned
        }
        if entries.contains(where: {
            switch $0 {
            case .missed: true
            case .brick(let brick): brick.isMissed
            default: false
            }
        }) {
            return .missed
        }
        return nil
    }
}
