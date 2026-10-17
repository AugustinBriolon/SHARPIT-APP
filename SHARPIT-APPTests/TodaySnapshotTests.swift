import Foundation
import SwiftData
import Testing
@testable import Sharpit

@MainActor
private func leaPlate(
    statusLabel: String = "Léger",
    instruction: String? = "Reste en endurance facile.",
    signals: [LimiterSignalCode] = [.sleepShort],
    stateCode: VerdictStateCode? = .trainEasy
) -> InkPlateModel {
    InkPlateModel(
        statusLabel: statusLabel,
        headline: "",
        actionLine: nil,
        limitingCause: nil,
        confidencePct: 70,
        confidenceLabel: "fiable",
        packTier: nil,
        estimationGaps: [],
        posture: .steady,
        instruction: instruction,
        limiterSignals: signals,
        showHeadline: false,
        stateCode: stateCode
    )
}

@MainActor
private func leaFold(dayId: String = TrainingDayId.today()) -> TodayFold {
    TodayFold(
        trainingDayId: dayId,
        plate: leaPlate(),
        sessions: [],
        gauges: [],
        consistency: nil,
        weather: nil
    )
}

@MainActor
@Test func snapshotRepositoryRoundTripsGlossaryCache() throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let fold = leaFold()

    try TodaySnapshotRepository.save(fold, context: context)
    let loaded = try #require(try TodaySnapshotRepository.load(
        trainingDayId: fold.trainingDayId,
        context: context
    ))

    #expect(loaded.statusLabel == "Léger")
    #expect(loaded.instruction == "Reste en endurance facile.")
    #expect(loaded.limiterSignalCodes == ["sleep_short"])
    #expect(loaded.stateCode == "TRAIN_EASY")
}

@MainActor
@Test func snapshotRepositoryUpsertsSameTrainingDay() throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    var fold = leaFold()

    try TodaySnapshotRepository.save(fold, context: context)
    fold.plate.statusLabel = "Repos"
    try TodaySnapshotRepository.save(fold, context: context)

    let count = try context.fetchCount(FetchDescriptor<TodayDaySnapshot>())
    #expect(count == 1)

    let loaded = try TodaySnapshotRepository.load(
        trainingDayId: fold.trainingDayId,
        context: context
    )
    #expect(loaded?.statusLabel == "Repos")
}

@MainActor
@Test func storeHydratesFromSnapshotBeforeNetwork() async throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let fold = leaFold()
    try TodaySnapshotRepository.save(fold, context: context)

    let client = FailingTodayClient()
    let store = TodayStore(client: client, modelContext: context, dayReads: DayReadCache())
    await store.load(resetToLoading: true)

    guard case .loaded(let cached) = store.phase else {
        Issue.record("Expected cached fold after transport failure")
        return
    }
    #expect(cached.trainingDayId == fold.trainingDayId)
    #expect(cached.plate.statusLabel == "Léger")
    #expect(cached.plate.instruction == "Reste en endurance facile.")
    // Glossary-only: no session cards until the network answers.
    #expect(cached.sessions.isEmpty)
}

/// Tab return re-fires `load` while LoadGate skips the network. Replacing the live fold with
/// the glossary snapshot used to blank sessions/gauges until pull-to-refresh.
@MainActor
@Test func tabReturnKeepsLiveFoldInsteadOfGlossarySnapshot() async throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let store = TodayStore(
        client: FixtureTodayClient(),
        tokenProvider: { "token" },
        modelContext: context
    )
    await store.load(resetToLoading: true)
    guard case .loaded(let first) = store.phase else {
        Issue.record("expected loaded fold after first load")
        return
    }
    #expect(!first.sessions.isEmpty)
    #expect(!first.gauges.isEmpty)

    await store.load(resetToLoading: false)
    guard case .loaded(let again) = store.phase else {
        Issue.record("expected loaded fold after tab return")
        return
    }
    #expect(again.sessions.count == first.sessions.count)
    #expect(again.gauges.map(\.key) == first.gauges.map(\.key))
}

private struct FailingTodayClient: TodayServing {
    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse {
        throw SharpitAPIError.transport
    }
}

/// CloudKit refuses a `#Unique` constraint, so the repository enforces day-uniqueness on read
/// (`docs/adr/0007`). Two replicated rows must collapse to the newest, not accumulate.
@MainActor
@Test func todayNeverKeepsTwoRowsForOneDay() throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let dayId = TrainingDayId.today()
    let cache = TodaySnapshotCache(fold: leaFold(dayId: dayId))
    let data = try JSONEncoder().encode(cache)

    context.insert(TodayDaySnapshot(
        trainingDayId: dayId,
        fetchedAt: Date(timeIntervalSince1970: 1_000_000),
        payloadJSON: data
    ))
    context.insert(TodayDaySnapshot(
        trainingDayId: dayId,
        fetchedAt: Date(timeIntervalSince1970: 2_000_000),
        payloadJSON: data
    ))
    try context.save()

    let loaded = try TodaySnapshotRepository.load(trainingDayId: dayId, context: context)

    #expect(loaded?.trainingDayId == dayId)
    #expect(try context.fetch(FetchDescriptor<TodayDaySnapshot>()).count == 1)
}

/// A row replicated before the app could write its payload reads as absent rather than
/// crashing: `payloadJSON` is optional because CloudKit requires it to be.
@MainActor
@Test func aRowWithoutItsPayloadReadsAsAbsent() throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let snapshot = TodayDaySnapshot(
        trainingDayId: TrainingDayId.today(),
        payloadJSON: Data()
    )
    snapshot.payloadJSON = nil
    context.insert(snapshot)
    try context.save()

    #expect(try TodaySnapshotRepository.load(trainingDayId: TrainingDayId.today(), context: context) == nil)
}

/// A legacy full `V1TodayResponse` blob fails glossary decode and is dropped.
@MainActor
@Test func legacyFullPayloadSnapshotIsDropped() throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let dayId = TrainingDayId.today()
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    context.insert(TodayDaySnapshot(
        trainingDayId: dayId,
        payloadJSON: try JSONEncoder().encode(response)
    ))
    try context.save()

    #expect(try TodaySnapshotRepository.load(trainingDayId: dayId, context: context) == nil)
}

/// Apple forbids HealthKit data in iCloud, and every cached model holds some (`docs/adr/0009`).
@Test func theOnDiskCacheNeverReplicatesToICloud() {
    #expect(SharpitPersistence.configuration(inMemory: false).cloudKitContainerIdentifier == nil)
}

/// No iCloud entitlement either, so a later configuration change cannot quietly turn it back on.
@Test func theAppIsNotEntitledToICloud() throws {
    let entitlements = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SHARPIT-APP/SharpIt.entitlements")
    let plist = try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: entitlements), format: nil) as? [String: Any]
    )
    #expect(plist["com.apple.developer.icloud-services"] == nil)
    #expect(plist["com.apple.developer.icloud-container-identifiers"] == nil)
}

@Test func aSnapshotPaintsThePlateAndLeavesTheRestUnknown() {
    let fold = TodaySnapshotCache(fold: leaFold(dayId: "2026-10-16")).asFold()
    // Unknown, not empty: Résumé holds the session's place instead of calling it a rest day.
    #expect(fold.isPlateOnly)
    #expect(fold.sessions.isEmpty)
}
