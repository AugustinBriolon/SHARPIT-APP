import Foundation
import SwiftData

/// The last answer the app got for one request, kept so a screen can paint before the network
/// replies (`docs/adr/0008`).
///
/// One model for every screen rather than one per feature: the rows differ only by which
/// request they answer, and `key` says which. Today and the journal keep their own models
/// because they cache a composed day rather than a single response.
///
/// CloudKit-shaped like the rest of the cache (`docs/adr/0007`): no `#Unique`, a default for
/// every attribute, an optional payload. Uniqueness is enforced on read.
@Model
final class CachedResponse {
    /// What this row answers — `ResponseCacheKey` builds it, never a literal at a call site.
    var key: String = ""
    var fetchedAt: Date = Date.distantPast
    @Attribute(.externalStorage) var payloadJSON: Data?

    init(key: String, fetchedAt: Date = .now, payloadJSON: Data?) {
        self.key = key
        self.fetchedAt = fetchedAt
        self.payloadJSON = payloadJSON
    }
}

/// The keys a cached response can have.
///
/// An enum rather than free strings so two screens cannot collide on one row, and so a key
/// that varies by day or by week says so in its own name.
nonisolated enum ResponseCacheKey {
    static let athleteProfile = "athlete-profile"
    static let bodyComposition = "body-composition"
    static let activities = "activities"
    static let syncStatus = "sync-status"
    static let coachConversations = "coach-conversations"
    static let thresholdHistory = "threshold-history"

    /// A plan week, addressed by the Monday it starts on: the plan is read a week at a time.
    static func planWeek(startingOn day: String) -> String { "plan-week:\(day)" }

    static func sleepDay(_ trainingDayId: String) -> String { "sleep:\(trainingDayId)" }
    static func recoveryDay(_ trainingDayId: String) -> String { "recovery:\(trainingDayId)" }
}

/// Reads and writes cached responses. Stateless, like the other repositories.
///
/// Every method swallows its own failures and returns nothing rather than throwing: a cache is
/// a convenience, and no screen should fail because its cache did.
enum ResponseCache {
    /// The cached answer for a key, or nil when there is none the app can still read.
    static func read<Payload: Decodable>(
        _ type: Payload.Type,
        key: String,
        context: ModelContext?
    ) -> Payload? {
        guard let context, let row = newest(key: key, context: context), let data = row.payloadJSON else {
            return nil
        }
        // A payload the app can no longer decode is treated as absent: the network answer is a
        // moment away, and a decode failure must never be what the athlete sees. This happens
        // for real when a wire type gains a required field.
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func write<Payload: Encodable>(
        _ payload: Payload,
        key: String,
        context: ModelContext?
    ) {
        guard let context, let data = try? JSONEncoder().encode(payload) else { return }
        if let row = newest(key: key, context: context) {
            row.payloadJSON = data
            row.fetchedAt = .now
        } else {
            context.insert(CachedResponse(key: key, payloadJSON: data))
        }
        try? context.save()
    }

    /// When the cached answer for a key was written, so a caller can decide it is too old to
    /// paint. Nil when nothing is cached.
    static func fetchedAt(key: String, context: ModelContext?) -> Date? {
        guard let context else { return nil }
        return newest(key: key, context: context)?.fetchedAt
    }

    /// The most recent row for a key, deleting any older duplicate.
    ///
    /// Replaces the `#Unique` CloudKit refuses: two devices can each insert a row for the same
    /// key before either has seen the other's, so the read path is where both become visible.
    private static func newest(key: String, context: ModelContext) -> CachedResponse? {
        let wanted = key
        let descriptor = FetchDescriptor<CachedResponse>(
            predicate: #Predicate { $0.key == wanted },
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        guard let rows = try? context.fetch(descriptor), let newest = rows.first else { return nil }
        for stale in rows.dropFirst() {
            context.delete(stale)
        }
        return newest
    }
}
