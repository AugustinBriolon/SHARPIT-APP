import Foundation

/// The server's race projection (`V1RaceProjection`) as the goal page reads it: the finish and
/// its range, the gap to the aim, how far to trust it, what would sharpen it, and each leg with
/// where its pace came from. The app never computes a projection itself.
struct RaceProjectionReadout: Sendable, Equatable {
    struct Leg: Sendable, Equatable, Identifiable {
        let segment: RaceLegSegment
        /// « d'après tes courses récentes »; nil when the server did not say.
        let sourceLabel: String?

        var id: Int { segment.id }
        var timeLabel: String { RaceTime.clock(segment.durationSec) }
    }

    /// A point of the trajectory chart: a week's race-day projection, or today's.
    struct TrajectoryPoint: Sendable, Equatable {
        let date: Date
        let finishSec: Double
    }

    let projection: V1RaceProjection
    /// Where the current projection sits on the trajectory.
    let now: Date

    init(_ projection: V1RaceProjection, now: Date = Date()) {
        self.projection = projection
        self.now = now
    }

    /// « 5h41 », at race day.
    var finishLabel: String { GoalAnalyticsEngine.formatDuration(projection.finishSec) }

    /// « 5h35 – 5h48 »
    var rangeLabel: String {
        "\(GoalAnalyticsEngine.formatDuration(projection.lowSec)) – \(GoalAnalyticsEngine.formatDuration(projection.highSec))"
    }

    /// « −7:12 vs objectif »; nil when the race names no target.
    var delta: RaceDelta? { projection.deltaSec.map(RaceDelta.init(seconds:)) }

    var confidenceLabel: String? {
        switch projection.confidence {
        case .low?: "fiabilité faible"
        case .medium?: "fiabilité moyenne"
        case .high?: "fiabilité bonne"
        case nil: nil
        }
    }

    /// « Si c'était aujourd'hui : 5h52 »
    var todayLine: String? {
        projection.todaySec.map { "Si c'était aujourd'hui : \(GoalAnalyticsEngine.formatDuration($0))" }
    }

    /// « Régularité : 82 % des séances faites · fiabilité moyenne »: how far to trust the range.
    var confidenceLine: String? {
        let regularity = projection.regularity.map { value in
            "Régularité : \(Int((min(max(value, 0), 1) * 100).rounded())) % des séances faites"
        }
        let parts = [regularity, confidenceLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The weekly race-day projections then the current one; empty below two points, a line of
    /// one point saying nothing.
    var trajectory: [TrajectoryPoint] {
        let points = projection.history.map { TrajectoryPoint(date: $0.date, finishSec: $0.finishSec) }
            + [TrajectoryPoint(date: now, finishSec: projection.finishSec)]
        return points.count >= 2 ? points : []
    }

    /// « −22 min en 8 semaines »; nil without a trajectory spanning a week.
    var trajectoryLine: String? {
        guard let first = trajectory.first, let last = trajectory.last else { return nil }
        let weeks = Int((last.date.timeIntervalSince(first.date) / 604_800).rounded())
        guard weeks >= 1 else { return nil }
        let span = weeks == 1 ? "1 semaine" : "\(weeks) semaines"
        let change = last.finishSec - first.finishSec
        let minutes = Int((abs(change) / 60).rounded())
        guard minutes > 0 else { return "stable en \(span)" }
        let amount = minutes < 60 ? "\(minutes) min" : GoalAnalyticsEngine.formatDuration(abs(change))
        return "\(change < 0 ? "−" : "+")\(amount) en \(span)"
    }

    var missing: [String] { projection.missing.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }

    var legs: [Leg] {
        let timed = projection.legs.filter { $0.sec > 0 }
        let total = timed.reduce(0) { $0 + $1.sec }
        guard total > 0 else { return [] }
        return timed.enumerated().map { index, leg in
            Leg(
                segment: RaceLegSegment(
                    id: index,
                    sport: Self.sport(leg.kind),
                    label: Self.sport(leg.kind)?.label ?? leg.kind.rawValue.uppercased(),
                    durationSec: leg.sec,
                    fraction: leg.sec / total
                ),
                sourceLabel: leg.source.map(Self.sourceLabel)
            )
        }
    }

    /// « Prévu 6:05 · Réalisé 5:40 » against a frozen pre-race projection; « Prévu (recalculé) »
    /// when the server re-projected after the race, so the comparison stays honest.
    func plannedVsActual(actualSeconds: Double) -> String {
        let planned = projection.frozenAt == nil ? "Prévu (recalculé)" : "Prévu"
        return "\(planned) \(GoalFormat.hoursMinutes(projection.finishSec)) · Réalisé \(GoalFormat.hoursMinutes(actualSeconds))"
    }

    private static func sport(_ kind: V1RaceProjection.LegKind) -> V1ActivityType? {
        switch kind {
        case .swim: .swim
        case .bike: .bike
        case .run: .run
        case .t1, .t2: nil
        }
    }

    private static func sourceLabel(_ source: V1RaceProjection.LegSource) -> String {
        switch source {
        case .history: "d'après ton historique"
        case .recent: "d'après tes courses récentes"
        case .profile: "valeur du profil"
        case .default: "valeur par défaut"
        }
    }
}
