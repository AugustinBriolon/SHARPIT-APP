import Foundation
import SwiftData

/// Offline paint for Aujourd'hui: glossary codes and labels only — never the full API day.
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

/// What the app may keep on disk for Aujourd'hui — verdict / instruction / chips, no health measures.
struct TodaySnapshotCache: Codable, Equatable, Sendable {
    var trainingDayId: String
    var stateCode: String?
    var statusLabel: String
    var instruction: String?
    var limiterSignalCodes: [String]
    var confidenceLabel: String?
    var confidencePct: Int?
    var vsYesterdayLabel: String?

    init(fold: TodayFold) {
        trainingDayId = fold.trainingDayId
        switch fold.plate.stateCode {
        case .unknown(let raw)?: stateCode = raw.isEmpty ? nil : raw
        case let code?: stateCode = code.wireValue
        case nil: stateCode = nil
        }
        statusLabel = fold.plate.statusLabel
        instruction = fold.plate.safeInstruction
        limiterSignalCodes = fold.plate.limiterSignals.compactMap { code in
            switch code {
            case .unknown(let raw): raw.isEmpty ? nil : raw
            default: code.wireValue
            }
        }
        confidenceLabel = fold.plate.confidenceLabel
        confidencePct = fold.plate.confidencePct
        vsYesterdayLabel = fold.plate.vsYesterdayLabel
    }

    /// A fold with only the plate filled — sessions / gauges wait for the network.
    func asFold() -> TodayFold {
        let signals = limiterSignalCodes.compactMap { LimiterSignalCode(wire: $0) }
        let code = stateCode.map { VerdictStateCode(wire: $0) }
        return TodayFold(
            trainingDayId: trainingDayId,
            plate: InkPlateModel(
                statusLabel: statusLabel,
                headline: "",
                actionLine: nil,
                limitingCause: nil,
                confidencePct: confidencePct,
                confidenceLabel: confidenceLabel,
                packTier: nil,
                estimationGaps: [],
                posture: .uncertain,
                explanationEssential: nil,
                explanationExpert: nil,
                instruction: instruction,
                limiterSignals: signals,
                vsYesterdayLabel: vsYesterdayLabel,
                showHeadline: false,
                stateCode: TodayFoldMapper.resolvedStateCode(code)
            ),
            sessions: [],
            gauges: [],
            consistency: nil,
            weather: nil,
            isPlateOnly: true
        )
    }
}

enum SharpitPersistence {
    /// The cache, on this iPhone only.
    ///
    /// Never iCloud: every model holds health-derived data — sleep, weight, recovery, the
    /// athlete's own journal answers — and Apple forbids storing HealthKit data in iCloud
    /// (`docs/adr/0009`). The cache is only a cache: every write goes to `/api`, and the
    /// server's echo overwrites it. Nor the device backup, for the same reason (`docs/adr/0017`).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = configuration(inMemory: inMemory)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if !inMemory { BackupExclusion.excludeStore(at: configuration.url) }
        return container
    }

    static let schema = Schema([TodayDaySnapshot.self, JournalDaySnapshot.self, CachedResponse.self])

    static func configuration(inMemory: Bool) -> ModelConfiguration {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
    }
}

enum TodaySnapshotRepository {
    /// Only today's snapshot (device calendar) is returned — yesterday's is discarded.
    static func load(trainingDayId: String, context: ModelContext, todayId: String = TrainingDayId.today()) throws -> TodaySnapshotCache? {
        guard trainingDayId == todayId else { return nil }
        guard let snapshot = try newest(trainingDayId: trainingDayId, context: context),
              let payload = snapshot.payloadJSON else {
            return nil
        }
        // Legacy full `V1TodayResponse` blobs fail this decode — treat as missing.
        guard let cache = try? JSONDecoder().decode(TodaySnapshotCache.self, from: payload) else {
            context.delete(snapshot)
            try? context.save()
            return nil
        }
        guard cache.trainingDayId == todayId else { return nil }
        return cache
    }

    static func save(_ fold: TodayFold, context: ModelContext) throws {
        let cache = TodaySnapshotCache(fold: fold)
        let data = try JSONEncoder().encode(cache)
        let dayId = fold.trainingDayId
        if let existing = try newest(trainingDayId: dayId, context: context) {
            existing.payloadJSON = data
            existing.fetchedAt = .now
        } else {
            context.insert(TodayDaySnapshot(trainingDayId: dayId, payloadJSON: data))
        }
        try context.save()
    }

    /// The most recent row for a day, deleting any older duplicate.
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
