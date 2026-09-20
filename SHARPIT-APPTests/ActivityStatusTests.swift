import Foundation
import Testing
@testable import Sharpit

private func decodeStore(_ json: String) throws -> V1ActivityStatusStore {
    try JSONDecoder().decode(V1ActivityStatusEnvelope.self, from: Data(json.utf8)).store
}

private func encodedWrite(_ write: V1ActivityStatusWrite) throws -> [String: Any] {
    let data = try JSONEncoder().encode(write)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

// MARK: - Wire

@Test func anOpenEndedStatusDecodes() throws {
    let store = try decodeStore("""
    { "store": { "version": 2, "status": "injured",
      "retention": { "kind": "until_modified" }, "travelId": null } }
    """)

    #expect(store.status == .injured)
    #expect(store.retention == .untilModified)
    #expect(store.travelId == nil)
}

@Test func aDeadlineDecodesWithItsDay() throws {
    let store = try decodeStore("""
    { "store": { "version": 2, "status": "paused",
      "retention": { "kind": "until_date", "untilDate": "2026-10-02" }, "travelId": "trip-1" } }
    """)

    #expect(store.retention == .untilDate("2026-10-02"))
    #expect(store.travelId == "trip-1")
}

/// The web writes `until_date` without a day when a row is half-written. Reading that
/// as a deadline would expire the mode on a date the app made up.
@Test func aDeadlineWithoutADayFallsBackToOpenEnded() throws {
    let store = try decodeStore("""
    { "store": { "version": 2, "status": "sick", "retention": { "kind": "until_date" } } }
    """)

    #expect(store.retention == .untilModified)
}

@Test func goingBackToActiveDropsTheDeadlineAndTheTrip() throws {
    let body = try encodedWrite(
        V1ActivityStatusWrite(
            status: .active,
            retention: .untilDate("2026-10-02"),
            travelId: "trip-1"
        )
    )

    #expect(body["status"] as? String == "active")
    #expect(body["retention"] == nil)
    #expect(body["travelId"] is NSNull)
}

/// An omitted key would let the row keep the trip the web attached to the pause.
@Test func aNonPausedModeSendsAnExplicitNullTrip() throws {
    let body = try encodedWrite(
        V1ActivityStatusWrite(status: .injured, retention: .untilModified, travelId: "trip-1")
    )

    #expect(body["travelId"] is NSNull)
    #expect((body["retention"] as? [String: Any])?["kind"] as? String == "until_modified")
}

@Test func aPauseKeepsItsTripAndItsDeadline() throws {
    let body = try encodedWrite(
        V1ActivityStatusWrite(status: .paused, retention: .untilDate("2026-10-02"), travelId: "trip-1")
    )

    #expect(body["travelId"] as? String == "trip-1")
    let retention = body["retention"] as? [String: Any]
    #expect(retention?["kind"] as? String == "until_date")
    #expect(retention?["untilDate"] as? String == "2026-10-02")
}

// MARK: - Dates

@Test func aDayStringRoundTrips() {
    let date = ActivityStatusDate.date(from: "2026-10-02")
    #expect(date != nil)
    #expect(ActivityStatusDate.string(from: date!) == "2026-10-02")
}

/// A mode ending today would expire on the next read and look like an accident.
@Test func afreshDeadlineIsAWeekOut() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 8))!

    let until = ActivityStatusDate.defaultUntil(from: now, calendar: calendar)

    #expect(ActivityStatusDate.string(from: until, calendar: calendar) == "2026-09-27")
}

// MARK: - Store

private actor StubActivityStatusClient: ActivityStatusServing {
    private var store: V1ActivityStatusStore
    private let failsWrite: Bool
    private(set) var writes: [V1ActivityStatusWrite] = []

    init(store: V1ActivityStatusStore = V1ActivityStatusStore(), failsWrite: Bool = false) {
        self.store = store
        self.failsWrite = failsWrite
    }

    func activityStatus(token _: String) async throws -> V1ActivityStatusStore { store }

    func setActivityStatus(
        _ write: V1ActivityStatusWrite,
        token _: String
    ) async throws -> V1ActivityStatusStore {
        writes.append(write)
        if failsWrite { throw SharpitAPIError.server }
        store = V1ActivityStatusStore(
            status: write.status,
            retention: write.retention ?? .untilModified,
            travelId: write.travelId
        )
        return store
    }

    func recordedWrites() -> [V1ActivityStatusWrite] { writes }
}

@MainActor
@Test func theStoreKeepsWhatTheServerAnswers() async {
    let client = StubActivityStatusClient()
    let store = ActivityStatusStore(client: client, tokenProvider: { "token" })

    await store.load()
    await store.apply(status: .sick, retention: .untilDate("2026-10-02"))

    #expect(store.store.status == .sick)
    #expect(store.store.retention == .untilDate("2026-10-02"))
    #expect(store.phase == .ready)
}

/// The chip must not claim a mode the server refused.
@MainActor
@Test func aRefusedWriteRestoresThePreviousMode() async {
    let client = StubActivityStatusClient(failsWrite: true)
    let store = ActivityStatusStore(client: client, tokenProvider: { "token" })

    await store.load()
    await store.apply(status: .injured, retention: .untilModified)

    #expect(store.store.status == .active)
    #expect(store.phase == .failed("Ton statut n'a pas pu être enregistré."))
}

@MainActor
@Test func anExpiredSessionStopsTheStatusChip() async {
    let client = StubActivityStatusClient()
    let store = ActivityStatusStore(
        client: client,
        tokenProvider: { throw SharpitAPIError.unauthorized }
    )

    await store.load()

    #expect(store.phase == .failed("Session expirée. Reconnecte-toi."))
}
