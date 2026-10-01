import Foundation
import SwiftData

/// The last Today payload the app saw for a day, so the fold paints offline and before the
/// network answers.
///
/// No `#Unique` on `trainingDayId`: the schema stayed as CloudKit once required it
/// (`docs/adr/0007`), and uniqueness is enforced on the read path — see
/// `TodaySnapshotRepository.newest`.
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
    /// The cache, on this iPhone only.
    ///
    /// Never iCloud: every model holds health-derived data — sleep, weight, recovery, the
    /// athlete's own journal answers — and Apple forbids storing HealthKit data in iCloud
    /// (`docs/adr/0009`). The cache is only a cache: every write goes to `/api`, and the
    /// server's echo overwrites it.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [configuration(inMemory: inMemory)])
    }

    static let schema = Schema([TodayDaySnapshot.self, JournalDaySnapshot.self, CachedResponse.self])

    static func configuration(inMemory: Bool) -> ModelConfiguration {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
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
    /// This replaces the `#Unique` constraint the schema does not declare (see the type).
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
