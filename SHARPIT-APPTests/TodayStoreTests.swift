import Foundation
import SwiftData
import Testing
@testable import Sharpit

private struct StubTodayClient: TodayServing {
    enum Mode: Sendable {
        case success
        case unauthorized
    }

    let mode: Mode

    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse {
        switch mode {
        case .success:
            return try await FixtureTodayClient().today(trainingDayId: trainingDayId, token: token)
        case .unauthorized:
            throw SharpitAPIError.unauthorized
        }
    }
}

@MainActor
@Test func todayStoreMapsLoadedFold() async {
    let store = TodayStore(client: StubTodayClient(mode: .success), tokenProvider: { "" })
    await store.load(resetToLoading: true)
    guard case .loaded(let fold) = store.phase else {
        Issue.record("expected loaded phase")
        return
    }
    // FixtureTodayClient ships the additive verdict vocabulary (PR #154 tags), not the
    // legacy « FEU VERT » label still present in full.json for decode backward-compat.
    #expect(fold.plate.statusLabel == "Léger")
    #expect(fold.plate.stateCode == .trainEasy)
    #expect(fold.plate.showHeadline == false)
    #expect(fold.plate.instruction == "Reste en endurance facile.")
    #expect(fold.plate.explanationEssential == "Ton corps est prêt pour une séance légère.")
    #expect(fold.plate.limiterSignals == [.sleepShort])
    #expect(fold.plate.vsYesterdayLabel == "Comme hier")
    #expect(fold.gauges.map(\.key) == [.sleep, .recovery])
    #expect(fold.sessions.first?.sport == "Course")
}

@MainActor
@Test func todayStoreMapsUnauthorized() async throws {
    AuthSession.shared.resetForTests()
    defer { AuthSession.shared.resetForTests() }
    let container = try SharpitPersistence.makeContainer(inMemory: true)
    let defaults = try #require(UserDefaults(suiteName: "TodayUnauthorized-\(UUID().uuidString)"))
    let disk = ActivityDiskCache(
        directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    )
    AuthSession.shared.bind(context: ModelContext(container), defaults: defaults, disk: disk)
    AuthSession.shared.refreshToken = { nil }
    AuthSession.shared.performSignOut = {}

    let store = TodayStore(client: StubTodayClient(mode: .unauthorized), tokenProvider: { "" })
    await store.load(resetToLoading: true)
    #expect(store.phase == .unauthorized)
    #expect(AuthSession.shared.expiredNotice)
}

@MainActor
@Test func todayStoreRefreshStaysLoaded() async {
    let store = TodayStore(client: StubTodayClient(mode: .success), tokenProvider: { "" })
    await store.load(resetToLoading: true)
    guard case .loaded = store.phase else {
        Issue.record("expected loaded before refresh")
        return
    }
    await store.refresh()
    guard case .loaded = store.phase else {
        Issue.record("expected loaded after refresh")
        return
    }
}

private actor RequestedDays {
    var ids: [String] = []
    func note(_ id: String) { ids.append(id) }
}

private struct RecordingTodayClient: TodayServing {
    let days: RequestedDays

    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse {
        await days.note(trainingDayId)
        return try await FixtureTodayClient().today(trainingDayId: trainingDayId, token: token)
    }
}

@MainActor
@Test func aPickedDayIsReadThenTodayFollowsTodayAgain() async throws {
    let days = RequestedDays()
    let store = TodayStore(client: RecordingTodayClient(days: days), tokenProvider: { "token" })
    let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: .now))

    await store.select(day: yesterday)
    #expect(!store.isToday)
    #expect(store.dayId == TrainingDayId.today(now: yesterday))

    await store.select(day: .now)
    #expect(store.isToday)
    #expect(await days.ids == [TrainingDayId.today(now: yesterday), TrainingDayId.today()])
}
