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
    /// What to do, in order — resolved server-side like a planned session's.
    let breakdown: V1PlannedSessionBreakdown?
    /// The session as the server sent it, prescriptions included: sent back whole to be added
    /// to the plan, so nothing the app does not model is lost on the way.
    let raw: JSONValue?

    enum CodingKeys: String, CodingKey {
        case dayOffset, date, startTime, type, intensity, title, description
        case durationMin, load, rationale, decisionId, breakdown
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
        breakdown = try? container.decodeIfPresent(V1PlannedSessionBreakdown.self, forKey: .breakdown)
        raw = try? JSONValue(from: decoder)
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
        decisionId: String? = nil,
        breakdown: V1PlannedSessionBreakdown? = nil
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
        self.breakdown = breakdown
        raw = nil
    }

    /// Whether a session streamed mid-generation is far enough along to show: its day and its
    /// title are written.
    var isDrafted: Bool { !date.isEmpty && !title.isEmpty && title != "Séance" }

    /// What `/api/v1/coach/plan/insert` receives for this session.
    var insertBody: JSONValue {
        if let raw { return raw }
        let optional = { (value: String?) in value.map(JSONValue.string) ?? .null }
        return .object([
            "date": .string(date),
            "startTime": optional(startTime),
            "type": .string(type.rawValue),
            "intensity": .string(intensity),
            "title": .string(title),
            "description": .string(description),
            "durationMin": .number(durationMin),
            "load": .number(load),
            "decisionId": optional(decisionId),
        ])
    }
}

/// The server's safety check on one proposed session (the web's plan Gate). A rejected session
/// can never be stored — the server refuses it with a 422 — so it is never offered to add.
nonisolated struct V1GateVerdict: Codable, Sendable, Hashable {
    nonisolated struct Finding: Codable, Sendable, Hashable {
        let severity: String
        let rationale: String
    }

    /// `ACCEPTED`, `WARNING`, `REQUIRES_CONFIRMATION` or `REJECTED`.
    let status: String
    var findings: [Finding] = []

    var isRejected: Bool { status == "REJECTED" }

    /// The worst finding's words, for a line under the session.
    var reason: String? { findings.first { $0.severity == status }?.rationale ?? findings.first?.rationale }
}

nonisolated struct V1PlanGate: Codable, Sendable, Hashable {
    var sessions: [V1GateVerdict] = []
}

nonisolated struct V1GeneratedPlan: Codable, Sendable {
    let summary: String
    let startDate: String?
    let sessions: [V1GeneratedSession]
    var gate: V1PlanGate?

    enum CodingKeys: String, CodingKey {
        case summary, startDate, sessions, gate
    }

    init(summary: String, startDate: String? = nil, sessions: [V1GeneratedSession], gate: V1PlanGate? = nil) {
        self.summary = summary
        self.startDate = startDate
        self.sessions = sessions
        self.gate = gate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        sessions = (try? container.decode([V1GeneratedSession].self, forKey: .sessions)) ?? []
        gate = try? container.decodeIfPresent(V1PlanGate.self, forKey: .gate)
    }

    /// The Gate's verdict on the session at `index`, in the order the sessions came.
    func verdict(at index: Int) -> V1GateVerdict? {
        guard let verdicts = gate?.sessions, verdicts.indices.contains(index) else { return nil }
        return verdicts[index]
    }

    /// The sessions the plan may take: every one the Gate did not reject.
    var insertableIndices: Set<Int> {
        Set(sessions.indices.filter { verdict(at: $0)?.isRejected != true })
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
    /// The change as the server sent it, prescriptions included: sent back whole to be applied
    /// (`/api/v1/coach/adapt/apply`), so the coach's steps are not lost on the way.
    let raw: JSONValue?

    enum CodingKeys: String, CodingKey {
        case action, sessionId, date, type, intensity, title, description
        case durationMin, load, reason, decisionId
    }

    /// What `/api/v1/coach/adapt/apply` receives for this change.
    var applyBody: JSONValue {
        if let raw { return raw }
        let optional = { (value: String?) in value.map(JSONValue.string) ?? .null }
        let number = { (value: Double?) in value.map(JSONValue.number) ?? .null }
        return .object([
            "action": .string(action.rawValue),
            "sessionId": optional(sessionId),
            "date": optional(date),
            "type": optional(type?.rawValue),
            "intensity": optional(intensity),
            "title": optional(title),
            "description": optional(description),
            "durationMin": number(durationMin),
            "load": number(load),
            "reason": .string(reason),
            "decisionId": optional(decisionId),
        ])
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
        raw = try? JSONValue(from: decoder)
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
        raw = nil
    }
}

nonisolated struct V1AdaptPlanResult: Codable, Sendable, Hashable {
    let summary: String
    let changes: [V1AdaptChange]
}
