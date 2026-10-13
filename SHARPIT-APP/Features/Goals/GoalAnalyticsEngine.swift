import Foundation

// MARK: - Models

struct GoalVolumeStats: Sendable, Equatable {
    let sessionsDone: Int
    let durationSeconds: Double
    let durationLabel: String
    let topSportLabel: String?
    let sessionHint: String
    let durationHint: String

    static let empty = GoalVolumeStats(
        sessionsDone: 0,
        durationSeconds: 0,
        durationLabel: "—",
        topSportLabel: nil,
        sessionHint: "Aucune séance liée pour l’instant",
        durationHint: "Temps consacré"
    )
}

// MARK: - Analytics Engine

enum GoalAnalyticsEngine {

    // MARK: - Volume Calculation

    static func computeVolumeStats(
        goal: V1Goal,
        sessions: [V1PlannedSessionItem],
        activities: [V1ActivityListItem] = [],
        now: Date = Date()
    ) -> GoalVolumeStats {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: goal.createdAt ?? .distantPast)
        // A race run closes its preparation on race day; what came after is the next block.
        let end = goal.targetDate.flatMap { day in
            day < now ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) : nil
        } ?? .distantFuture
        let inWindow = { (date: Date) in date >= start && date < end }
        let activityById = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })

        // Planned sessions tied to the goal and done; else every session done while preparing it.
        let doneSessions = sessions.filter { session in
            session.goalId == goal.id && inWindow(session.date)
                && (session.completed == true || session.activityId != nil)
        }
        let done: [(type: String, duration: Double)] = doneSessions.isEmpty
            ? activities.filter { inWindow($0.date) }.map { ($0.type.rawValue, $0.duration ?? 0) }
            : doneSessions.map { session in
                // Embedded activity duration > list activity duration > planned minutes.
                let listed = session.activityId.flatMap { activityById[$0] }
                let duration = [session.activity?.duration, listed?.duration, session.durationMin.map { Double($0 * 60) }]
                    .compactMap { $0 }.first { $0 > 0 } ?? 0
                let type = session.type ?? session.activity?.type ?? listed?.type.rawValue ?? "OTHER"
                return (type, duration)
            }

        guard !done.isEmpty else {
            return .empty
        }

        var totalDurationSec: Double = 0
        var durationByType: [String: Double] = [:]
        var countByType: [String: Int] = [:]
        for item in done {
            let normalizedType = item.type.uppercased()
            totalDurationSec += item.duration
            durationByType[normalizedType, default: 0] += item.duration
            countByType[normalizedType, default: 0] += 1
        }

        // Top sport by duration
        let sortedSports = durationByType.sorted { (left, right) -> Bool in
            if left.value != right.value {
                return left.value > right.value
            }
            return (countByType[left.key] ?? 0) > (countByType[right.key] ?? 0)
        }

        let topSportName = sortedSports.first.flatMap { sportDisplayName($0.key) }
        let hint = topSportName.map { "Mix : \($0) en tête" } ?? "Depuis le début du cap"

        return GoalVolumeStats(
            sessionsDone: done.count,
            durationSeconds: totalDurationSec,
            durationLabel: formatDuration(totalDurationSec),
            topSportLabel: topSportName,
            sessionHint: hint,
            durationHint: totalDurationSec <= 0 ? "Temps consacré" : hint
        )
    }

    static func sportDisplayName(_ type: String) -> String {
        switch type.uppercased() {
        case "BIKE": "Vélo"
        case "RUN": "Course"
        case "SWIM": "Natation"
        case "STRENGTH": "Force"
        case "HIKE": "Randonnée"
        case "TRIATHLON": "Triathlon"
        default: "Autre"
        }
    }

    static func formatDuration(_ totalSeconds: Double) -> String {
        let total = Int(totalSeconds.rounded())
        guard total > 0 else { return "—" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%dh%02d", hours, minutes)
        } else {
            return "\(minutes)min"
        }
    }
}
