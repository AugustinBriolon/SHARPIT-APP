import Foundation
import SwiftData

/// The last Today payload the app saw for a day, so the fold paints offline and before the
/// network answers.
///
/// No `#Unique` on `trainingDayId` and a default for every attribute: CloudKit accepts neither
/// a uniqueness constraint nor a non-optional attribute without one (`docs/adr/0007`).
/// Uniqueness is enforced on the read path instead — see `TodaySnapshotRepository.newest`.
@Model
final class TodayDaySnapshot {
    var trainingDayId: String = ""
    var fetchedAt: Date = Date.distantPast
    @Attribute(.externalStorage) var payloadJSON: Data?

    init(trainingDayId: String, fetchedAt: Date = .now, payloadJSON: Data) {
        self.trainingDayId = trainingDayId
        self.fetchedAt = fetchedAt
        self.payloadJSON = payloadJSON
    }
}

enum SharpitPersistence {
    static let cloudKitContainerId = "iCloud.app.sharpit.ios"

    /// The cache, replicated through the athlete's **private** CloudKit database.
    ///
    /// Private and never public: these snapshots hold sleep, weight and the athlete's own
    /// journal answers. The cache is still only a cache — every write goes to `/api`, and the
    /// server's echo overwrites whatever a device replicated (`docs/adr/0007`).
    ///
    /// An in-memory store skips CloudKit entirely: a test must not reach the network, and a
    /// preview has no account.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([TodayDaySnapshot.self, JournalDaySnapshot.self, CachedResponse.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .private(cloudKitContainerId)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

enum TodaySnapshotRepository {
    static func load(trainingDayId: String, context: ModelContext) throws -> V1TodayResponse? {
        guard let snapshot = try newest(trainingDayId: trainingDayId, context: context),
              let payload = snapshot.payloadJSON else {
            return nil
        }
        return try JSONDecoder().decode(V1TodayResponse.self, from: payload)
    }

    static func save(_ response: V1TodayResponse, context: ModelContext) throws {
        let data = try JSONEncoder().encode(response)
        let dayId = response.trainingDayId
        if let existing = try newest(trainingDayId: dayId, context: context) {
            existing.payloadJSON = data
            existing.fetchedAt = .now
        } else {
            context.insert(
                TodayDaySnapshot(trainingDayId: dayId, payloadJSON: data)
            )
        }
        try context.save()
    }

    /// The most recent row for a day, deleting any older duplicate.
    ///
    /// This replaces the `#Unique` constraint CloudKit refuses: two devices can each insert a
    /// row for the same day before either has seen the other's, so the read path is the first
    /// place both are visible.
    private static func newest(
        trainingDayId: String,
        context: ModelContext
    ) throws -> TodayDaySnapshot? {
        let dayId = trainingDayId
        let descriptor = FetchDescriptor<TodayDaySnapshot>(
            predicate: #Predicate { $0.trainingDayId == dayId },
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        let rows = try context.fetch(descriptor)
        guard let newest = rows.first else { return nil }
        for stale in rows.dropFirst() {
            context.delete(stale)
        }
        return newest
    }
}
