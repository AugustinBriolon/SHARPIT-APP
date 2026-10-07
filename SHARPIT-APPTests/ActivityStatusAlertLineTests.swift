import Testing
@testable import Sharpit

// MARK: - Alert copy mapping

@Test func alertLineIsEmptyForActive() {
    #expect(ActivityStatusId.active.alertLine.isEmpty)
}

@Test func alertLineIsNonEmptyForAllNonActiveStatuses() {
    for status in ActivityStatusId.allCases where status != .active {
        #expect(!status.alertLine.isEmpty, "\(status) should have an alert line")
    }
}

@Test func alertLineReusesStatusTone() {
    #expect(ActivityStatusId.injured.tone == SharpitColor.signalRisk)
    #expect(ActivityStatusId.sick.tone == SharpitColor.signalCaution)
    #expect(ActivityStatusId.paused.tone == SharpitColor.signalNeutral)
    #expect(ActivityStatusId.active.tone == SharpitColor.signalRecovery)
}

@Test func alertLineReusesStatusSymbol() {
    #expect(ActivityStatusId.paused.symbolName == "pause.circle")
    #expect(ActivityStatusId.injured.symbolName == "bandage")
    #expect(ActivityStatusId.sick.symbolName == "thermometer.medium")
    #expect(ActivityStatusId.active.symbolName == "figure.run")
}

// MARK: - Visibility mapping

@Test func alertIsHiddenWhenStatusIsActive() {
    #expect(ActivityStatusId.active.alertLine.isEmpty)
}

@Test func alertTextForPaused() {
    #expect(ActivityStatusId.paused.alertLine == "En pause — le plan est en veille jusqu'à reprise.")
}

@Test func alertTextForInjured() {
    #expect(ActivityStatusId.injured.alertLine == "Blessé — priorité sécurité, les séances à risque sont adaptées ou reportées.")
}

@Test func alertTextForSick() {
    #expect(ActivityStatusId.sick.alertLine == "Repos — reprenez quand le corps suit.")
}

// MARK: - Store.current mapping

/// Stub client that returns a fixed status.
private final class StubStatusClient: ActivityStatusServing {
    let status: ActivityStatusId
    init(status: ActivityStatusId) { self.status = status }

    func activityStatus(token _: String) async throws -> V1ActivityStatusStore {
        V1ActivityStatusStore(status: status, retention: .untilModified, travelId: nil)
    }

    func setActivityStatus(_ write: V1ActivityStatusWrite, token _: String) async throws -> V1ActivityStatusStore {
        V1ActivityStatusStore(status: write.status, retention: write.retention ?? .untilModified, travelId: write.travelId)
    }
}

@MainActor
@Test func storeCurrentReflectsServerStatus() async throws {
    let client = StubStatusClient(status: .injured)
    let store = ActivityStatusStore(client: client, tokenProvider: { "token" })
    await store.load()

    #expect(store.current == .injured)
    #expect(store.current != .active)
}

@MainActor
@Test func storeCurrentIsReadyAfterLoad() async throws {
    let client = StubStatusClient(status: .sick)
    let store = ActivityStatusStore(client: client, tokenProvider: { "token" })
    await store.load()

    #expect(store.phase == .ready)
    #expect(store.current == .sick)
}

@MainActor
@Test func alertHiddenWhenStoreCurrentIsActive() async throws {
    let client = StubStatusClient(status: .active)
    let store = ActivityStatusStore(client: client, tokenProvider: { "token" })
    await store.load()

    #expect(store.current == .active)
    #expect(store.current.alertLine.isEmpty)
}
