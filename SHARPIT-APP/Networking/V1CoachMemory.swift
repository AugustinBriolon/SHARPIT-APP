import Foundation

nonisolated enum CoachMemoryType: String, Codable, CaseIterable, Identifiable, Sendable {
    case travel = "TRAVEL"
    case constraint = "CONSTRAINT"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .travel: "Déplacement / voyage"
        case .constraint: "Contrainte"
        }
    }
}

nonisolated enum TravelTrainingConstraint: String, Codable, CaseIterable, Identifiable, Sendable {
    case full = "FULL"
    case reduced = "REDUCED"
    case mobilityOnly = "MOBILITY_ONLY"
    case none = "NONE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: "Entraînement normal"
        case .reduced: "Charge allégée"
        case .mobilityOnly: "Mobilité seule"
        case .none: "Pause complète"
        }
    }

    var badgeText: String {
        switch self {
        case .full: "Normal"
        case .reduced: "Allégé"
        case .mobilityOnly: "Mobilité"
        case .none: "Pause"
        }
    }
}

nonisolated struct CoachMemoryEntry: Identifiable, Codable, Sendable, Equatable {
    let id: String
    var type: CoachMemoryType
    var label: String?
    var locationLabel: String?
    var startDate: Date
    var endDate: Date
    var note: String?
    var trainingConstraint: TravelTrainingConstraint
    var allowedDisciplines: [String]?
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, label, locationLabel
        case startDate, endDate, note, trainingConstraint, allowedDisciplines, isActive
    }

    init(
        id: String = UUID().uuidString,
        type: CoachMemoryType,
        label: String? = nil,
        locationLabel: String? = nil,
        startDate: Date,
        endDate: Date,
        note: String? = nil,
        trainingConstraint: TravelTrainingConstraint = .full,
        allowedDisciplines: [String]? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.locationLabel = locationLabel
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.trainingConstraint = trainingConstraint
        self.allowedDisciplines = allowedDisciplines
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(CoachMemoryType.self, forKey: .type)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        locationLabel = try container.decodeIfPresent(String.self, forKey: .locationLabel)
        let startRaw = try container.decode(String.self, forKey: .startDate)
        let endRaw = try container.decode(String.self, forKey: .endDate)
        startDate = (try? Date.fromAPI(startRaw)) ?? Date()
        endDate = (try? Date.fromAPI(endRaw)) ?? Date()
        note = try container.decodeIfPresent(String.self, forKey: .note)
        trainingConstraint = (try? container.decode(TravelTrainingConstraint.self, forKey: .trainingConstraint)) ?? .full
        allowedDisciplines = try container.decodeIfPresent([String].self, forKey: .allowedDisciplines)
        isActive = (try? container.decodeIfPresent(Bool.self, forKey: .isActive)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(locationLabel, forKey: .locationLabel)
        try container.encode(startDate.toAPI, forKey: .startDate)
        try container.encode(endDate.toAPI, forKey: .endDate)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(trainingConstraint, forKey: .trainingConstraint)
        try container.encodeIfPresent(allowedDisciplines, forKey: .allowedDisciplines)
        try container.encode(isActive, forKey: .isActive)
    }

    var displayTitle: String {
        if let label, !label.isEmpty { return label }
        if let locationLabel, !locationLabel.isEmpty { return locationLabel }
        return type == .travel ? "Déplacement" : "Contrainte"
    }

    var formattedDateRange: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM"
        let startStr = fmt.string(from: startDate)
        let endStr = fmt.string(from: endDate)
        if startStr == endStr {
            return startStr
        }
        return "\(startStr) → \(endStr)"
    }
}

nonisolated struct CoachMemorySnapshot: Codable, Sendable, Equatable {
    var entries: [CoachMemoryEntry]
    var activeId: String?
    var profileContext: String

    enum CodingKeys: String, CodingKey {
        case entries, activeId, profileContext
    }

    init(entries: [CoachMemoryEntry] = [], activeId: String? = nil, profileContext: String = "") {
        self.entries = entries
        self.activeId = activeId
        self.profileContext = profileContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = (try? container.decode([CoachMemoryEntry].self, forKey: .entries)) ?? []
        activeId = try container.decodeIfPresent(String.self, forKey: .activeId)
        profileContext = (try? container.decodeIfPresent(String.self, forKey: .profileContext)) ?? ""
    }
}

nonisolated struct CreateCoachMemoryInput: Codable, Sendable {
    var type: CoachMemoryType
    var label: String?
    var locationLabel: String?
    var startDate: Date
    var endDate: Date
    var note: String?
    var trainingConstraint: TravelTrainingConstraint?
    var allowedDisciplines: [String]?

    enum CodingKeys: String, CodingKey {
        case type, label, locationLabel, startDate, endDate, note, trainingConstraint, allowedDisciplines
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(locationLabel, forKey: .locationLabel)
        try container.encode(startDate.toAPI, forKey: .startDate)
        try container.encode(endDate.toAPI, forKey: .endDate)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(trainingConstraint, forKey: .trainingConstraint)
        try container.encodeIfPresent(allowedDisciplines, forKey: .allowedDisciplines)
    }
}
