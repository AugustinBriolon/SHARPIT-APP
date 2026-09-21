import Foundation
import SwiftData

/// The last journal the app saw for a day, so the screen opens on content rather than on
/// five empty plates.
///
/// Three payloads rather than one: the entry, the preferences that decide what is asked, and
/// the derived checklist. A day whose preferences are cached but whose entry is not is a real
/// state — the preferences read can succeed while the entry read fails — so each is optional
/// and read independently.
///
/// Written to be CloudKit-replicable from the start (`docs/adr/0007`): no `#Unique`, a default
/// for every attribute, and optional payloads. CloudKit accepts none of the three otherwise,
/// and retrofitting them later would be a schema migration.
@Model
final class JournalDaySnapshot {
    var trainingDayId: String = ""
    var fetchedAt: Date = Date.distantPast
    @Attribute(.externalStorage) var entryJSON: Data?
    @Attribute(.externalStorage) var prefsJSON: Data?
    @Attribute(.externalStorage) var signalsJSON: Data?

    init(
        trainingDayId: String,
        fetchedAt: Date = .now,
        entryJSON: Data? = nil,
        prefsJSON: Data? = nil,
        signalsJSON: Data? = nil
    ) {
        self.trainingDayId = trainingDayId
        self.fetchedAt = fetchedAt
        self.entryJSON = entryJSON
        self.prefsJSON = prefsJSON
        self.signalsJSON = signalsJSON
    }
}

/// What one cached day yields. Every part is optional: a cache is a convenience, and a
/// half-written one still paints half a screen.
nonisolated struct CachedJournalDay: Equatable, Sendable {
    var entry: V1DayJournalEntry?
    var prefs: JournalPrefs?
    var signals: V1JournalDaySignals?

    var isEmpty: Bool { entry == nil && prefs == nil && signals == nil }
}

/// The only accessor for the journal's cache, stateless like `TodaySnapshotRepository`.
enum JournalSnapshotRepository {
    static func load(trainingDayId: String, context: ModelContext) throws -> CachedJournalDay {
        guard let snapshot = try newest(trainingDayId: trainingDayId, context: context) else {
            return CachedJournalDay()
        }
        return CachedJournalDay(
            entry: decode(V1DayJournalEntry.self, from: snapshot.entryJSON),
            prefs: decodedPrefs(from: snapshot.prefsJSON),
            signals: decode(V1JournalDaySignals.self, from: snapshot.signalsJSON)
        )
    }

    /// Writes the day, replacing whatever was there.
    ///
    /// Each payload is written only when given, so saving an entry after a failed preferences
    /// read does not erase preferences the app still holds.
    static func save(
        trainingDayId: String,
        entry: V1DayJournalEntry? = nil,
        prefs: JournalPrefs? = nil,
        signals: V1JournalDaySignals? = nil,
        context: ModelContext
    ) throws {
        let snapshot = try newest(trainingDayId: trainingDayId, context: context)
            ?? {
                let fresh = JournalDaySnapshot(trainingDayId: trainingDayId)
                context.insert(fresh)
                return fresh
            }()

        if let entry { snapshot.entryJSON = try JSONEncoder().encode(entry) }
        if let prefs {
            snapshot.prefsJSON = try JSONSerialization.data(
                withJSONObject: prefs.raw.mapValues(\.foundationObject)
            )
        }
        if let signals { snapshot.signalsJSON = try JSONEncoder().encode(signals) }
        snapshot.fetchedAt = .now
        try context.save()
    }

    /// The most recent row for a day, deleting any older duplicate.
    ///
    /// A `#Unique` constraint would do this in the store, but CloudKit refuses one, so the
    /// uniqueness is enforced on read instead: two devices can both insert the same day
    /// before either has seen the other's row.
    private static func newest(
        trainingDayId: String,
        context: ModelContext
    ) throws -> JournalDaySnapshot? {
        let dayId = trainingDayId
        let descriptor = FetchDescriptor<JournalDaySnapshot>(
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

    /// A cache the app can no longer read is treated as absent: the network answer is a
    /// moment away, and a decode failure must never be what the athlete sees.
    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func decodedPrefs(from data: Data?) -> JournalPrefs? {
        guard let data,
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let raw) = value else { return nil }
        return JournalPrefs(raw: raw)
    }
}
