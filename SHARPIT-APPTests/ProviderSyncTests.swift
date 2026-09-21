import Foundation
import Testing
@testable import Sharpit

private actor SyncCalls {
    private(set) var statusReads = 0
    private(set) var pulls = 0
    func readStatus() { statusReads += 1 }
    func pull() { pulls += 1 }
}

private struct StubSync: SyncServing {
    let calls: SyncCalls
    var last: Date?
    var providers = [V1SyncProvider(key: "garmin", label: "Garmin", lastSyncAt: nil)]
    var pullError: SharpitAPIError?
    var pullDelay: Duration = .zero

    func syncStatus(token: String) async throws -> V1SyncStatus {
        await calls.readStatus()
        return V1SyncStatus(lastSyncAt: last, providers: providers)
    }

    func sync(token: String) async throws -> V1SyncStatus {
        await calls.pull()
        try await Task.sleep(for: pullDelay)
        if let pullError { throw pullError }
        return V1SyncStatus(lastSyncAt: Date(timeIntervalSince1970: 1_000_000), providers: providers)
    }
}

private let now = Date(timeIntervalSince1970: 1_000_000)

@MainActor
private func store(_ stub: StubSync) -> ProviderSyncStore {
    ProviderSyncStore(client: stub, tokenProvider: { "t" }, now: { now })
}

@MainActor
@Test func aRecentPullIsNotRepeated() async {
    let calls = SyncCalls()
    let sync = store(StubSync(calls: calls, last: now.addingTimeInterval(-5 * 60)))
    #expect(await sync.syncIfStale() == false)
    #expect(await calls.pulls == 0)
}

@MainActor
@Test func aStalePullRunsAndAsksForAReload() async {
    let calls = SyncCalls()
    let sync = store(StubSync(calls: calls, last: now.addingTimeInterval(-40 * 60)))
    #expect(await sync.syncIfStale() == true)
    #expect(await calls.pulls == 1)
    #expect(sync.lastSyncAt == now)
    #expect(sync.state == .idle)
}

@MainActor
@Test func withoutProvidersNothingIsPulled() async {
    let calls = SyncCalls()
    let sync = store(StubSync(calls: calls, last: nil, providers: []))
    #expect(await sync.syncIfStale() == false)
    #expect(await sync.syncNow() == false)
    #expect(await calls.pulls == 0)
}

/// A pull that ran moments ago is not a failure: the server already holds fresh data.
@MainActor
@Test func aRateLimitedPullStaysQuiet() async {
    let calls = SyncCalls()
    let sync = store(StubSync(calls: calls, last: nil, pullError: .rateLimited))
    #expect(await sync.syncIfStale() == false)
    #expect(sync.state == .idle)
}

@MainActor
@Test func aFailedPullSaysSo() async {
    let calls = SyncCalls()
    let sync = store(StubSync(calls: calls, last: nil, pullError: .server))
    _ = await sync.syncNow()
    #expect(sync.state == .failed)
}

/// Launch and foregrounding arrive together: one pull, not two.
@MainActor
@Test func concurrentTriggersShareOnePull() async {
    let calls = SyncCalls()
    let sync = store(StubSync(calls: calls, last: nil, pullDelay: .milliseconds(100)))
    async let first = sync.syncIfStale()
    async let second = sync.syncIfStale()
    _ = await (first, second)
    #expect(await calls.pulls == 1)
}

@Test func theSyncLineReadsTheAgeOfTheData() {
    #expect(SyncReadout.caption(state: .syncing, lastSyncAt: nil, now: now) == "Synchronisation…")
    #expect(SyncReadout.caption(state: .idle, lastSyncAt: nil, now: now) == nil)
    #expect(SyncReadout.caption(state: .idle, lastSyncAt: now.addingTimeInterval(-20), now: now) == "Synchronisé à l'instant")
    #expect(SyncReadout.caption(state: .idle, lastSyncAt: now.addingTimeInterval(-12 * 60), now: now) == "Synchronisé il y a 12 min")
    #expect(SyncReadout.caption(state: .idle, lastSyncAt: now.addingTimeInterval(-3 * 3_600), now: now) == "Synchronisé il y a 3 h")
    #expect(SyncReadout.caption(state: .failed, lastSyncAt: now, now: now) == "Synchronisation impossible")
}

@Test func syncStatusDecodesMillisecondTimestamps() throws {
    let json = #"{"apiVersion":1,"lastSyncAt":"2026-09-21T09:00:00.123Z","providers":[{"key":"garmin","label":"Garmin","lastSyncAt":"2026-09-21T09:00:00.123Z"}],"needsReconnect":[]}"#
    let status = try JSONDecoder().decode(V1SyncStatus.self, from: Data(json.utf8))
    #expect(status.lastSyncAt != nil)
    #expect(status.providers.first?.lastSyncAt == status.lastSyncAt)
}
