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

struct GoalPositionSegment: Identifiable, Sendable, Equatable {
    let id: String
    let kind: String
    let label: String
    let timeLabel: String
    let sharePct: Int

    init(id: String = UUID().uuidString, kind: String, label: String, timeLabel: String, sharePct: Int) {
        self.id = id
        self.kind = kind
        self.label = label
        self.timeLabel = timeLabel
        self.sharePct = sharePct
    }
}

struct GoalRaceProjectionResult: Sendable, Equatable {
    let projectedSeconds: Int
    let projectedLabel: String
    let targetLabel: String
    let gapLabel: String
    let isAhead: Bool
    let segments: [GoalPositionSegment]
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

    // MARK: - Target Parsing

    /// Parses targets like "Sub 6h", "Sous 6h", "6h", "5h15", "1:30:00", "42.195"
    static func parseTargetSeconds(_ raw: String?) -> Int? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }

        // Strip prefix: Sub, Sous, <
        let cleaned = trimmed
            .replacingOccurrences(of: "^(sub|sous|<)\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)

        // Pattern 1: XhYY or Xh
        if let match = cleaned.range(of: #"^(\d+)\s*h\s*(\d{1,2})?$"#, options: .regularExpression) {
            let sub = String(cleaned[match])
            let parts = sub.split(separator: "h")
            if let h = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
                let m = parts.count > 1 ? (Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0) : 0
                return h * 3600 + m * 60
            }
        }

        // Pattern 2: H:MM:SS or MM:SS
        let timeParts = cleaned.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if timeParts.count == 3 {
            return timeParts[0] * 3600 + timeParts[1] * 60 + timeParts[2]
        } else if timeParts.count == 2 {
            return timeParts[0] * 60 + timeParts[1]
        }

        return nil
    }

    // MARK: - Triathlon Projection

    enum TriathlonFormat: String, Sendable {
        case half
        case full
        case olympic
        case sprint

        var distances: (swimM: Double, bikeM: Double, runM: Double) {
            switch self {
            case .half: (1900, 90_000, 21_097)
            case .full: (3800, 180_000, 42_195)
            case .olympic: (1500, 40_000, 10_000)
            case .sprint: (750, 20_000, 5000)
            }
        }

        var defaultTransitions: (t1: Int, t2: Int) {
            switch self {
            case .half: (126, 79)
            case .full: (300, 240)
            case .olympic: (210, 150)
            case .sprint: (180, 120)
            }
        }

        var brickRunSlowdownFactor: Double {
            switch self {
            case .half: 1.08
            case .full: 1.12
            case .olympic: 1.06
            case .sprint: 1.04
            }
        }
    }

    static func resolveTriathlonFormat(raceFormat: String?, title: String?) -> TriathlonFormat? {
        let combined = [raceFormat, title].compactMap { $0 }.joined(separator: " ").lowercased()
        if combined.contains("70.3") || combined.contains("half iron") || combined.contains("half-im") || (combined.contains("triathlon") && combined.contains("half")) {
            return .half
        }
        if combined.contains("ironman") || combined.contains("full iron") {
            return .full
        }
        if combined.contains("olympique") || combined.contains("olympic") {
            return .olympic
        }
        if combined.contains("sprint") {
            return .sprint
        }
        return nil
    }

    static func computeRaceProjection(
        goal: V1Goal,
        profile: V1AthleteProfile?,
        activities: [V1ActivityListItem] = []
    ) -> GoalRaceProjectionResult? {
        let targetSec = parseTargetSeconds(goal.targetPerformance) ?? 6 * 3600
        let targetDisplay = goal.targetPerformance ?? "6h00"

        if let format = resolveTriathlonFormat(raceFormat: goal.raceFormat, title: goal.title) {
            return computeTriathlonFinish(
                format: format,
                targetSeconds: targetSec,
                targetDisplay: targetDisplay,
                profile: profile,
                activities: activities
            )
        }

        // Running race projection fallback
        let titleLower = (goal.title + " " + (goal.raceFormat ?? "")).lowercased()
        if titleLower.contains("marathon") && !titleLower.contains("semi") {
            return computeRunningProjection(meters: 42195, targetSeconds: targetSec, targetDisplay: targetDisplay, profile: profile)
        } else if titleLower.contains("semi") || titleLower.contains("21") {
            return computeRunningProjection(meters: 21097, targetSeconds: targetSec, targetDisplay: targetDisplay, profile: profile)
        } else if titleLower.contains("10k") || titleLower.contains("10 km") {
            return computeRunningProjection(meters: 10000, targetSeconds: targetSec, targetDisplay: targetDisplay, profile: profile)
        }

        return nil
    }

    private static func computeTriathlonFinish(
        format: TriathlonFormat,
        targetSeconds: Int,
        targetDisplay: String,
        profile: V1AthleteProfile?,
        activities: [V1ActivityListItem]
    ) -> GoalRaceProjectionResult {
        let dist = format.distances

        // 1. Swim: CSS pace sec/100m * 1.07 open water
        let cssPace = profile?.swimCssSecPer100m ?? 103.5
        let openWaterPace = cssPace * 1.07
        let swimSec = Int(((dist.swimM / 100.0) * openWaterPace).rounded())

        // 2. Transitions
        let (t1Sec, t2Sec) = format.defaultTransitions

        // 3. Bike: from bike activities or default speed
        let bikeActivities = activities.filter { $0.type == .bike }
        let bikeSpeeds: [Double] = bikeActivities.compactMap { act in
            guard let dist = act.distanceM, let dur = act.duration, dist >= (format.distances.bikeM * 0.35), dur > 0 else { return nil }
            let speedMs = dist / dur
            return (speedMs > 4 && speedMs < 18) ? speedMs : nil
        }

        let chosenSpeedMs: Double
        if !bikeSpeeds.isEmpty {
            let sorted = bikeSpeeds.sorted()
            chosenSpeedMs = sorted[sorted.count / 2] // median
        } else {
            // Speed calculated from FTP (~207W) or default 32.1 km/h = 8.91 m/s
            chosenSpeedMs = 8.91
        }
        let bikeSec = Int((dist.bikeM / chosenSpeedMs).rounded())

        // 4. Run: threshold pace * brick factor
        let runThresholdPaceSecPerKm = profile?.runThresholdPaceSecPerKm ?? 306.0 // 5:06/km
        let runPaceSecPerKm = runThresholdPaceSecPerKm * format.brickRunSlowdownFactor
        let runSec = Int(((dist.runM / 1000.0) * runPaceSecPerKm).rounded())

        let totalSeconds = swimSec + t1Sec + bikeSec + t2Sec + runSec
        let isAhead = totalSeconds <= targetSeconds
        let diffSec = abs(totalSeconds - targetSeconds)

        let gapM = diffSec / 60
        let gapS = diffSec % 60
        let gapLabel = isAhead
            ? String(format: "-%dm%02ds sous la cible", gapM, gapS)
            : String(format: "+%dm%02ds au-dessus de la cible", gapM, gapS)

        let total = Double(totalSeconds)
        let segments: [GoalPositionSegment] = [
            GoalPositionSegment(kind: "swim", label: "Natation", timeLabel: formatTimeHMS(swimSec), sharePct: Int((Double(swimSec) / total * 100).rounded())),
            GoalPositionSegment(kind: "t1", label: "T1", timeLabel: formatTimeMS(t1Sec), sharePct: Int((Double(t1Sec) / total * 100).rounded())),
            GoalPositionSegment(kind: "bike", label: "Vélo", timeLabel: formatTimeHMS(bikeSec), sharePct: Int((Double(bikeSec) / total * 100).rounded())),
            GoalPositionSegment(kind: "t2", label: "T2", timeLabel: formatTimeMS(t2Sec), sharePct: Int((Double(t2Sec) / total * 100).rounded())),
            GoalPositionSegment(kind: "run", label: "Course", timeLabel: formatTimeHMS(runSec), sharePct: Int((Double(runSec) / total * 100).rounded()))
        ]

        return GoalRaceProjectionResult(
            projectedSeconds: totalSeconds,
            projectedLabel: formatTimeHMS(totalSeconds),
            targetLabel: targetDisplay,
            gapLabel: gapLabel,
            isAhead: isAhead,
            segments: segments
        )
    }

    private static func computeRunningProjection(
        meters: Double,
        targetSeconds: Int,
        targetDisplay: String,
        profile: V1AthleteProfile?
    ) -> GoalRaceProjectionResult {
        let thresholdPace = profile?.runThresholdPaceSecPerKm ?? 270.0
        // Riegel formula approximation: T2 = T1 * (D2 / D1)^1.06
        let projectedSec = Int((meters / 1000.0 * thresholdPace * 1.05).rounded())
        let isAhead = projectedSec <= targetSeconds
        let diffSec = abs(projectedSec - targetSeconds)
        let gapM = diffSec / 60
        let gapS = diffSec % 60
        let gapLabel = isAhead
            ? String(format: "-%dm%02ds sous la cible", gapM, gapS)
            : String(format: "+%dm%02ds au-dessus", gapM, gapS)

        return GoalRaceProjectionResult(
            projectedSeconds: projectedSec,
            projectedLabel: formatTimeHMS(projectedSec),
            targetLabel: targetDisplay,
            gapLabel: gapLabel,
            isAhead: isAhead,
            segments: [
                GoalPositionSegment(kind: "run", label: "Course", timeLabel: formatTimeHMS(projectedSec), sharePct: 100)
            ]
        )
    }

    public static func formatTimeHMS(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    public static func formatTimeMS(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
