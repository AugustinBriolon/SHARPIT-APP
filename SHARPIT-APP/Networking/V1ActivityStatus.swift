import Foundation

/// The athlete's training mode. It outlives a day, unlike a journal entry, and biases
/// what the plan and the coach are allowed to ask for.
nonisolated enum ActivityStatusId: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case injured
    case sick

    var label: String {
        switch self {
        case .active: "Actif"
        case .paused: "En pause"
        case .injured: "Blessé"
        case .sick: "Malade"
        }
    }

    var hint: String {
        switch self {
        case .active: "En routine d'entraînement"
        case .paused: "Pause dans l'entraînement"
        case .injured: "En convalescence après une blessure"
        case .sick: "Repos pour cause de maladie"
        }
    }

    /// How planning and the coach bias while the mode is on, in the web's words.
    var planningImpact: String {
        switch self {
        case .active: "Charge et séances suivent le plan."
        case .paused: "Pas de charge volontaire — plan en veille jusqu'à reprise."
        case .injured: "Priorité sécurité — adapter ou reporter les séances à risque."
        case .sick: "Repos avant la charge — reprendre seulement quand le corps suit."
        }
    }

    var symbolName: String {
        switch self {
        case .active: "figure.run"
        case .paused: "pause.circle"
        case .injured: "bandage"
        case .sick: "thermometer.medium"
        }
    }
}

/// How long the mode holds. `active` is always open-ended.
nonisolated enum ActivityStatusRetention: Equatable, Sendable {
    case untilModified
    /// `yyyy-MM-dd`, the last day the mode applies. The server resolves a past date
    /// back to `active` on read, so the app never has to expire one itself.
    case untilDate(String)

    var untilDate: String? {
        if case .untilDate(let day) = self { day } else { nil }
    }
}

nonisolated extension ActivityStatusRetention: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case untilDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind)
        let day = try container.decodeIfPresent(String.self, forKey: .untilDate)
        if kind == "until_date", let day {
            self = .untilDate(day)
        } else {
            self = .untilModified
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .untilModified:
            try container.encode("until_modified", forKey: .kind)
        case .untilDate(let day):
            try container.encode("until_date", forKey: .kind)
            try container.encode(day, forKey: .untilDate)
        }
    }
}

nonisolated struct V1ActivityStatusStore: Codable, Equatable, Sendable {
    var status: ActivityStatusId
    var retention: ActivityStatusRetention
    /// Set by the web when a pause is a trip. The app does not model trips; it carries
    /// the id back unchanged so a status edit from the phone keeps the web's link.
    var travelId: String?

    init(
        status: ActivityStatusId = .active,
        retention: ActivityStatusRetention = .untilModified,
        travelId: String? = nil
    ) {
        self.status = status
        self.retention = retention
        self.travelId = travelId
    }
}

nonisolated struct V1ActivityStatusEnvelope: Decodable {
    let store: V1ActivityStatusStore
}

/// The PUT body, which is the store's fields unwrapped.
nonisolated struct V1ActivityStatusWrite: Encodable, Equatable, Sendable {
    let status: ActivityStatusId
    let retention: ActivityStatusRetention?
    let travelId: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case retention
        case travelId
    }

    /// `active` carries no retention: the server forces it open-ended anyway.
    init(status: ActivityStatusId, retention: ActivityStatusRetention, travelId: String?) {
        self.status = status
        self.retention = status == .active ? nil : retention
        self.travelId = status == .paused ? travelId : nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(retention, forKey: .retention)
        // Explicit null, not an omitted key: leaving a pause must drop the trip the
        // web attached to it rather than let the row keep it.
        if let travelId {
            try container.encode(travelId, forKey: .travelId)
        } else {
            try container.encodeNil(forKey: .travelId)
        }
    }
}
