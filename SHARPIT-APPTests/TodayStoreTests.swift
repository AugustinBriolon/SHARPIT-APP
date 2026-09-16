import Foundation
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
    #expect(fold.plate.statusLabel == "FEU VERT")
    #expect(fold.gauges.map(\.key) == [.sleep, .recovery])
    #expect(fold.sessions.first?.sport == "Course")
}

@MainActor
@Test func todayStoreMapsUnauthorized() async {
    let store = TodayStore(client: StubTodayClient(mode: .unauthorized), tokenProvider: { "" })
    await store.load(resetToLoading: true)
    #expect(store.phase == .unauthorized)
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
