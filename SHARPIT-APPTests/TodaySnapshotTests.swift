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
