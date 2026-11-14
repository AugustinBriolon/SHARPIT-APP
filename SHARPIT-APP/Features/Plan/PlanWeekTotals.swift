import Foundation

/// A week of the plan in three figures: sessions, volume and load, each as what was done over
/// what the week holds. Counted from the same entries Plan lists, so the rings and the list
/// always agree.
///
/// The week's whole is what was done plus what is still to do or was missed. A done session
/// counts for what was recorded, not for what had been prescribed: the prescription of a done
/// session is not in the entries.
struct PlanWeekTotals: Equatable, Sendable {
    var doneSessions = 0
    var totalSessions = 0
    var missedSessions = 0
    var doneMinutes = 0
    var totalMinutes = 0
    var doneLoad = 0.0
    var totalLoad = 0.0

    init(_ entries: [PlanEntry] = []) {
        for entry in entries {
            totalSessions += 1
            switch entry {
            case .executed(let executed):
                addDone(minutes: executed.activity.duration.map { Int(($0 / 60).rounded()) }, load: executed.activity.load)
            case .doneBrick(let brick):
                addDone(minutes: brick.totalDurationMin, load: brick.legs.compactMap(\.activity?.load).reduce(0, +))
            case .planned(let session):
                addAhead(minutes: session.durationMin, load: session.load)
            case .missed(let session):
                missedSessions += 1
                addAhead(minutes: session.durationMin, load: session.load)
            case .brick(let brick):
                if brick.isMissed { missedSessions += 1 }
                addAhead(minutes: brick.totalDurationMin, load: brick.totalLoad)
            }
        }
    }

    private mutating func addDone(minutes: Int?, load: Double?) {
        doneSessions += 1
        doneMinutes += minutes ?? 0
        totalMinutes += minutes ?? 0
        doneLoad += load ?? 0
        totalLoad += load ?? 0
    }

    private mutating func addAhead(minutes: Int?, load: Double?) {
        totalMinutes += minutes ?? 0
        totalLoad += load ?? 0
    }

    /// Nil for an empty denominator: a ring with nothing to measure draws no arc.
    static func fraction(_ done: Double, of total: Double) -> Double? {
        total > 0 ? min(done / total, 1) : nil
    }

    var sessionsFraction: Double? { Self.fraction(Double(doneSessions), of: Double(totalSessions)) }
    var volumeFraction: Double? { Self.fraction(Double(doneMinutes), of: Double(totalMinutes)) }
    var loadFraction: Double? { Self.fraction(doneLoad, of: totalLoad) }

    /// « 6 h 40 », « 45 min », « 2 h ».
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }
}
