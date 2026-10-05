import Foundation

/// `/api/v1/sensitive-zones` — the athlete's declared zones as the web follows them
/// (SHARPIT ADR-068): what each one does to the plan, how it evolved, the follow-up owed and
/// whether closing it is worth proposing. The app lays it out; it computes none of it.
nonisolated struct V1SensitiveZones: Decodable, Equatable, Sendable {
    let zones: [V1SensitiveZone]
    /// The body parts offered when declaring — each one checked against the plan.
    let bodyParts: [String]

    var open: [V1SensitiveZone] { zones.filter { !$0.isResolved } }
    var resolved: [V1SensitiveZone] { zones.filter(\.isResolved) }

    init(zones: [V1SensitiveZone] = [], bodyParts: [String] = []) {
        self.zones = zones
        self.bodyParts = bodyParts
    }

    private enum CodingKeys: String, CodingKey { case zones, bodyParts }

    /// A zone the app cannot read is dropped, not the whole page.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zones = (try? container.decode([TolerantZone].self, forKey: .zones))?.compactMap(\.value) ?? []
        bodyParts = (try? container.decode([String].self, forKey: .bodyParts)) ?? []
    }
}

private nonisolated struct TolerantZone: Decodable {
    let value: V1SensitiveZone?

    init(from decoder: Decoder) throws {
        value = try? V1SensitiveZone(from: decoder)
    }
}

nonisolated struct V1SensitiveZone: Decodable, Equatable, Identifiable, Hashable, Sendable {
    /// What the plan does with the zone.
    enum Strategy: String, Decodable, Sendable {
        case protect
        case progressive
        case correct
        case relapseWatch = "relapse_watch"
        case none
    }

    let id: String
    let title: String
    let category: String
    let categoryLabel: String
    let bodyPart: String?
    /// False when the plan check cannot see this zone (a free-text region).
    let bodyPartRecognized: Bool
    let side: String
    let sideLabel: String?
    let status: String
    let statusLabel: String
    let severity: Int?
    let functionalImpact: String?
    let functionalImpactLabel: String?
    let description: String?
    let affectsTraining: Bool
    let startDate: Date
    let resolvedAt: Date?
    let strategy: Strategy
    let strategyLabel: String
    let strategyDetail: String
    let resolutionSuggested: Bool
    let recurrenceCount: Int
    let followUpQuestion: String?
    let upcomingSessionsLoading: Int
    /// Newest first.
    let timeline: [V1ZoneTimelineEntry]

    var isResolved: Bool { status == "RESOLVED" }

    /// « Genou · Gauche », or the category when no region was given.
    var place: String {
        let parts = [bodyPart, sideLabel].compactMap { $0 }
        return parts.isEmpty ? categoryLabel : parts.joined(separator: " · ")
    }

    /// The readings, oldest first, for the curve.
    var readings: [V1ZoneTimelineEntry] {
        timeline.filter { $0.kind == .reading && $0.severity != nil }.reversed()
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, categoryLabel, bodyPart, bodyPartRecognized, side, sideLabel
        case status, statusLabel, severity, functionalImpact, functionalImpactLabel, description
        case affectsTraining, startDate, resolvedAt, strategy, strategyLabel, strategyDetail
        case resolutionSuggested, recurrenceCount, followUpQuestion, upcomingSessionsLoading, timeline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decode(String.self, forKey: .category)
        categoryLabel = try c.decode(String.self, forKey: .categoryLabel)
        bodyPart = try c.decodeIfPresent(String.self, forKey: .bodyPart)
        bodyPartRecognized = (try? c.decode(Bool.self, forKey: .bodyPartRecognized)) ?? true
        side = (try? c.decode(String.self, forKey: .side)) ?? "NA"
        sideLabel = try c.decodeIfPresent(String.self, forKey: .sideLabel)
        status = try c.decode(String.self, forKey: .status)
        statusLabel = try c.decode(String.self, forKey: .statusLabel)
        severity = try c.decodeIfPresent(Int.self, forKey: .severity)
        functionalImpact = try c.decodeIfPresent(String.self, forKey: .functionalImpact)
        functionalImpactLabel = try c.decodeIfPresent(String.self, forKey: .functionalImpactLabel)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        affectsTraining = (try? c.decode(Bool.self, forKey: .affectsTraining)) ?? true
        startDate = try V1ZoneDate.decode(c, .startDate) ?? Date()
        resolvedAt = try V1ZoneDate.decode(c, .resolvedAt)
        // An unknown strategy reads as « no effect » rather than losing the zone.
        strategy = (try? c.decode(Strategy.self, forKey: .strategy)) ?? .none
        strategyLabel = try c.decode(String.self, forKey: .strategyLabel)
        strategyDetail = try c.decode(String.self, forKey: .strategyDetail)
        resolutionSuggested = (try? c.decode(Bool.self, forKey: .resolutionSuggested)) ?? false
        recurrenceCount = (try? c.decode(Int.self, forKey: .recurrenceCount)) ?? 0
        followUpQuestion = try c.decodeIfPresent(String.self, forKey: .followUpQuestion)
        upcomingSessionsLoading = (try? c.decode(Int.self, forKey: .upcomingSessionsLoading)) ?? 0
        timeline = (try? c.decode([V1ZoneTimelineEntry].self, forKey: .timeline)) ?? []
    }
}

nonisolated struct V1ZoneTimelineEntry: Decodable, Equatable, Identifiable, Hashable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case reading
        case status
    }

    let id: String
    let date: Date
    let kind: Kind
    let label: String
    let severity: Int?
    let functionalImpact: String?
    let comment: String?

    private enum CodingKeys: String, CodingKey {
        case id, date, kind, label, severity, functionalImpact, comment
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try V1ZoneDate.decode(c, .date) ?? Date()
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .reading
        label = try c.decode(String.self, forKey: .label)
        severity = try c.decodeIfPresent(Int.self, forKey: .severity)
        functionalImpact = try c.decodeIfPresent(String.self, forKey: .functionalImpact)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
    }
}

/// The web sends ISO 8601 with milliseconds; the default decoder reads neither.
private nonisolated enum V1ZoneDate {
    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) throws -> Date? {
        guard let text = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return parse(text)
    }

    static func parse(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
