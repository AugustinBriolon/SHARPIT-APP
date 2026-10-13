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
        let createdDate = goal.createdAt ?? .distantPast
        let calendar = Calendar.current
        let startOfDayCreated = calendar.startOfDay(for: createdDate)

        // 1. Linked sessions for this goal on or after created date
        let linked = sessions.filter { session in
            guard session.goalId == goal.id else { return false }
            let sessionDay = calendar.startOfDay(for: session.date)
            return sessionDay >= startOfDayCreated
        }

        guard !linked.isEmpty else {
            return .empty
        }

        // 2. Activity lookup map
        let activityById = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })

        // 3. Filter done sessions (completed or has activity)
        let doneSessions = linked.filter { session in
            session.completed == true || session.activityId != nil
        }

        var totalDurationSec: Double = 0
        var durationByType: [String: Double] = [:]
        var countByType: [String: Int] = [:]

        for session in doneSessions {
            // Determine duration: embedded activity duration > list activity duration > durationMin * 60
            let duration: Double
            if let embDur = session.activity?.duration, embDur > 0 {
                duration = embDur
            } else if let actId = session.activityId, let act = activityById[actId], let actDur = act.duration, actDur > 0 {
                duration = actDur
            } else if let min = session.durationMin, min > 0 {
                duration = Double(min * 60)
            } else {
                duration = 0
            }

            totalDurationSec += duration

            let rawType = session.type ?? session.activity?.type ?? (session.activityId.flatMap { activityById[$0]?.type.rawValue }) ?? "OTHER"
            let normalizedType = rawType.uppercased()

            durationByType[normalizedType, default: 0] += duration
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
            sessionsDone: doneSessions.count,
            durationSeconds: totalDurationSec,
            durationLabel: formatDuration(totalDurationSec),
            topSportLabel: topSportName,
            sessionHint: doneSessions.isEmpty ? "Aucune séance liée pour l’instant" : hint,
            durationHint: (doneSessions.isEmpty || totalDurationSec <= 0) ? "Temps consacré" : hint
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
