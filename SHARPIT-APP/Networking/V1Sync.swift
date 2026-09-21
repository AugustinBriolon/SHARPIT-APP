import Foundation

/// `GET /api/v1/sync-status` and `POST /api/v1/sync` — mirror `projectV1SyncStatus` on the web.
nonisolated struct V1SyncStatus: Decodable, Sendable, Equatable {
    let apiVersion: Int
    /// The most recent pull across connected providers.
    let lastSyncAt: Date?
    let providers: [V1SyncProvider]
    let needsReconnect: [String]

    private enum CodingKeys: String, CodingKey {
        case apiVersion, lastSyncAt, providers, needsReconnect
    }

    init(apiVersion: Int = 1, lastSyncAt: Date?, providers: [V1SyncProvider], needsReconnect: [String] = []) {
        self.apiVersion = apiVersion
        self.lastSyncAt = lastSyncAt
        self.providers = providers
        self.needsReconnect = needsReconnect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        lastSyncAt = try container.decodeIfPresent(String.self, forKey: .lastSyncAt).flatMap(V1SyncStatus.date)
        providers = try container.decode([V1SyncProvider].self, forKey: .providers)
        needsReconnect = try container.decodeIfPresent([String].self, forKey: .needsReconnect) ?? []
    }

    /// `toISOString()` always writes milliseconds, which the default ISO parser rejects.
    static func date(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

nonisolated struct V1SyncProvider: Decodable, Sendable, Equatable, Identifiable {
    let key: String
    let label: String
    let lastSyncAt: Date?

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, label, lastSyncAt
    }

    init(key: String, label: String, lastSyncAt: Date?) {
        self.key = key
        self.label = label
        self.lastSyncAt = lastSyncAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        lastSyncAt = try container.decodeIfPresent(String.self, forKey: .lastSyncAt).flatMap(V1SyncStatus.date)
    }
}
