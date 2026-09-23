import Foundation

// MARK: - Generated Plan (Remplir ma semaine)

nonisolated struct V1GeneratedSession: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(date)-\(dayOffset)-\(title)" }
    let dayOffset: Int
    let date: String
    let startTime: String?
    let type: V1ActivityType
    let intensity: String
    let title: String
    let description: String
    let durationMin: Double
    let load: Double
    let rationale: String?
    let decisionId: String?

    enum CodingKeys: String, CodingKey {
        case dayOffset, date, startTime, type, intensity, title, description
        case durationMin, load, rationale, decisionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayOffset = (try? container.decode(Int.self, forKey: .dayOffset)) ?? 0
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        let rawType = try container.decodeIfPresent(String.self, forKey: .type) ?? "OTHER"
        type = V1ActivityType(rawValue: rawType) ?? .other
        intensity = try container.decodeIfPresent(String.self, forKey: .intensity) ?? "ENDURANCE"
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Séance"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        durationMin = try container.decodeIfPresent(Double.self, forKey: .durationMin) ?? 0
        load = try container.decodeIfPresent(Double.self, forKey: .load) ?? 0
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        decisionId = try container.decodeIfPresent(String.self, forKey: .decisionId)
    }

    init(
        dayOffset: Int = 0,
        date: String,
        startTime: String? = nil,
        type: V1ActivityType,
        intensity: String,
        title: String,
        description: String,
        durationMin: Double,
        load: Double,
        rationale: String? = nil,
        decisionId: String? = nil
    ) {
        self.dayOffset = dayOffset
        self.date = date
        self.startTime = startTime
        self.type = type
        self.intensity = intensity
        self.title = title
        self.description = description
        self.durationMin = durationMin
        self.load = load
        self.rationale = rationale
        self.decisionId = decisionId
    }
}

nonisolated struct V1GeneratedPlan: Codable, Sendable {
    let summary: String
    let startDate: String?
    let sessions: [V1GeneratedSession]

    enum CodingKeys: String, CodingKey {
        case summary, startDate, sessions
    }

    init(summary: String, startDate: String? = nil, sessions: [V1GeneratedSession]) {
        self.summary = summary
        self.startDate = startDate
        self.sessions = sessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        sessions = (try? container.decode([V1GeneratedSession].self, forKey: .sessions)) ?? []
    }
}

// MARK: - Plan Adaptation (Ajuster le planning)

nonisolated enum V1AdaptAction: String, Codable, Sendable {
    case add = "ADD"
    case modify = "MODIFY"
    case remove = "REMOVE"

    var label: String {
        switch self {
        case .add: "Ajouter"
        case .modify: "Modifier"
        case .remove: "Supprimer"
        }
    }
}

nonisolated struct V1AdaptChange: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(action.rawValue)-\(sessionId ?? "")-\(date ?? "")-\(title ?? "")" }
    let action: V1AdaptAction
    let sessionId: String?
    let date: String?
    let type: V1ActivityType?
    let intensity: String?
    let title: String?
    let description: String?
    let durationMin: Double?
    let load: Double?
    let reason: String
    let decisionId: String?

    enum CodingKeys: String, CodingKey {
        case action, sessionId, date, type, intensity, title, description
        case durationMin, load, reason, decisionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(V1AdaptAction.self, forKey: .action)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        if let rawType = try container.decodeIfPresent(String.self, forKey: .type) {
            type = V1ActivityType(rawValue: rawType) ?? .other
        } else {
            type = nil
        }
        intensity = try container.decodeIfPresent(String.self, forKey: .intensity)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        durationMin = try container.decodeIfPresent(Double.self, forKey: .durationMin)
        load = try container.decodeIfPresent(Double.self, forKey: .load)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        decisionId = try container.decodeIfPresent(String.self, forKey: .decisionId)
    }

    init(
        action: V1AdaptAction,
        sessionId: String? = nil,
        date: String? = nil,
        type: V1ActivityType? = nil,
        intensity: String? = nil,
        title: String? = nil,
        description: String? = nil,
        durationMin: Double? = nil,
        load: Double? = nil,
        reason: String,
        decisionId: String? = nil
    ) {
        self.action = action
        self.sessionId = sessionId
        self.date = date
        self.type = type
        self.intensity = intensity
        self.title = title
        self.description = description
        self.durationMin = durationMin
        self.load = load
        self.reason = reason
        self.decisionId = decisionId
    }
}

nonisolated struct V1AdaptPlanResult: Codable, Sendable {
    let summary: String
    let changes: [V1AdaptChange]
}
