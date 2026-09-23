import Foundation

enum V1PlanPhase: String, Codable, Sendable, CaseIterable {
    case base = "BASE"
    case build = "BUILD"
    case peak = "PEAK"
    case taper = "TAPER"
    case race = "RACE"

    var label: String {
        switch self {
        case .base: "Base"
        case .build: "Développement"
        case .peak: "Spécifique"
        case .taper: "Affûtage"
        case .race: "Course"
        }
    }

    var shortLabel: String {
        switch self {
        case .base: "Base"
        case .build: "Dév."
        case .peak: "Spéc."
        case .taper: "Affût."
        case .race: "Course"
        }
    }
}

nonisolated struct V1PlanWeek: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let weekStart: Date
    let weekIndex: Int
    let phase: V1PlanPhase
    let targetLoad: Double
    let targetHours: Double?
    let focus: String?
    let isDeload: Bool

    enum CodingKeys: String, CodingKey {
        case id, weekStart, weekIndex, phase, targetLoad, targetHours, focus, isDeload
    }

    init(
        id: String = UUID().uuidString,
        weekStart: Date,
        weekIndex: Int,
        phase: V1PlanPhase,
        targetLoad: Double,
        targetHours: Double? = nil,
        focus: String? = nil,
        isDeload: Bool = false
    ) {
        self.id = id
        self.weekStart = weekStart
        self.weekIndex = weekIndex
        self.phase = phase
        self.targetLoad = targetLoad
        self.targetHours = targetHours
        self.focus = focus
        self.isDeload = isDeload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let rawDate = try container.decode(String.self, forKey: .weekStart)
        weekStart = (try? Date.fromAPI(rawDate)) ?? Date()
        weekIndex = try container.decode(Int.self, forKey: .weekIndex)
        phase = try container.decode(V1PlanPhase.self, forKey: .phase)
        targetLoad = try container.decode(Double.self, forKey: .targetLoad)
        targetHours = try container.decodeIfPresent(Double.self, forKey: .targetHours)
        focus = try container.decodeIfPresent(String.self, forKey: .focus)
        isDeload = (try? container.decode(Bool.self, forKey: .isDeload)) ?? false
    }
}

nonisolated struct V1TrainingPlan: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let goalId: String
    let raceDate: Date
    let startDate: Date
    let baselineCtl: Double?
    let summary: String?
    let status: String
    let weeks: [V1PlanWeek]

    enum CodingKeys: String, CodingKey {
        case id, goalId, raceDate, startDate, baselineCtl, summary, status, weeks
    }

    init(
        id: String,
        goalId: String,
        raceDate: Date,
        startDate: Date,
        baselineCtl: Double? = nil,
        summary: String? = nil,
        status: String = "ACTIVE",
        weeks: [V1PlanWeek]
    ) {
        self.id = id
        self.goalId = goalId
        self.raceDate = raceDate
        self.startDate = startDate
        self.baselineCtl = baselineCtl
        self.summary = summary
        self.status = status
        self.weeks = weeks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        goalId = try container.decode(String.self, forKey: .goalId)
        let rawRace = try container.decode(String.self, forKey: .raceDate)
        raceDate = (try? Date.fromAPI(rawRace)) ?? Date()
        let rawStart = try container.decode(String.self, forKey: .startDate)
        startDate = (try? Date.fromAPI(rawStart)) ?? Date()
        baselineCtl = try container.decodeIfPresent(Double.self, forKey: .baselineCtl)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        status = try container.decode(String.self, forKey: .status)
        weeks = try container.decode([V1PlanWeek].self, forKey: .weeks)
    }
}
