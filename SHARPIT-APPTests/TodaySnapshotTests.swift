import Foundation
import SwiftData
import Testing
@testable import Sharpit

@MainActor
@Test func snapshotRepositoryRoundTripsTodayPayload() throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))

    try TodaySnapshotRepository.save(response, context: context)
    let loaded = try TodaySnapshotRepository.load(
        trainingDayId: response.trainingDayId,
        context: context
    )

    #expect(loaded == response)
}

@MainActor
@Test func snapshotRepositoryUpsertsSameTrainingDay() throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    var response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))

    try TodaySnapshotRepository.save(response, context: context)
    response.verdict.headline = "Updated headline"
    try TodaySnapshotRepository.save(response, context: context)

    let count = try context.fetchCount(FetchDescriptor<TodayDaySnapshot>())
    #expect(count == 1)

    let loaded = try TodaySnapshotRepository.load(
        trainingDayId: response.trainingDayId,
        context: context
    )
    #expect(loaded?.verdict.headline == "Updated headline")
}

@MainActor
@Test func storeHydratesFromSnapshotBeforeNetwork() async throws {
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let context = ModelContext(container)
    var response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    // The store asks the cache for *today*, so the fixture has to be filed under today —
    // otherwise the test only passes on the day the fixture was captured.
    response.trainingDayId = TrainingDayId.today()
    try TodaySnapshotRepository.save(response, context: context)

    let client = FailingTodayClient()
    let store = TodayStore(client: client, modelContext: context)
    await store.load(resetToLoading: true)

    guard case .loaded(let fold) = store.phase else {
        Issue.record("Expected cached fold after transport failure")
        return
    }
    #expect(fold.trainingDayId == response.trainingDayId)
    #expect(fold.plate.headline == response.verdict.headline)
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
    let older = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    let dayId = older.trainingDayId

    context.insert(TodayDaySnapshot(
        trainingDayId: dayId,
        fetchedAt: Date(timeIntervalSince1970: 1_000_000),
        payloadJSON: try JSONEncoder().encode(older)
    ))
    context.insert(TodayDaySnapshot(
        trainingDayId: dayId,
        fetchedAt: Date(timeIntervalSince1970: 2_000_000),
        payloadJSON: try JSONEncoder().encode(older)
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
        trainingDayId: "2026-09-21",
        payloadJSON: Data()
    )
    snapshot.payloadJSON = nil
    context.insert(snapshot)
    try context.save()

    #expect(try TodaySnapshotRepository.load(trainingDayId: "2026-09-21", context: context) == nil)
}
