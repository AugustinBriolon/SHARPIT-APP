import Testing
@testable import Sharpit

private struct GoogleCalendarsLoadStub: GoogleCalendarsServing {
    var loadHandler: @Sendable () async throws -> [V1GoogleCalendar] = { [] }
    var selectHandler: @Sendable () async throws -> Void = {}

    init(
        handler: @escaping @Sendable () async throws -> [V1GoogleCalendar],
        selectHandler: @escaping @Sendable () async throws -> Void = {}
    ) {
        loadHandler = handler
        self.selectHandler = selectHandler
    }

    func googleCalendars(token: String) async throws -> [V1GoogleCalendar] {
        try await loadHandler()
    }

    func selectGoogleCalendar(calendarId: String, calendarName: String?, token: String) async throws {
        try await selectHandler()
    }
}

@Suite
struct GoogleCalendarPickerStoreTests {
    private let sample = V1GoogleCalendar(id: "cal-1", summary: "Sport", primary: false, isTarget: true)

    @Test @MainActor func cancelledReloadKeepsReadyWithCachedCalendars() async {
        final class CallCounter: @unchecked Sendable {
            var value = 0
        }
        let counter = CallCounter()
        let stub = GoogleCalendarsLoadStub {
            counter.value += 1
            if counter.value == 1 { return [sample] }
            throw CancellationError()
        }
        let store = GoogleCalendarPickerStore(client: stub, tokenProvider: { "tok" })
        await store.load()
        #expect(store.phase == .ready)
        await store.load()
        #expect(store.phase == .ready)
        #expect(store.calendars == [sample])
    }

    @Test @MainActor func cancelledInitialLoadOffersRetryInsteadOfEmptyReady() async {
        let stub = GoogleCalendarsLoadStub { throw CancellationError() }
        let store = GoogleCalendarPickerStore(client: stub, tokenProvider: { "tok" })
        await store.load()
        #expect(store.phase == .failed(.load("Chargement interrompu. Réessaie.")))
        #expect(store.calendars.isEmpty)
    }

    @Test @MainActor func cancelledSelectRestoresReadyAndReturnsFalse() async {
        let stub = GoogleCalendarsLoadStub(
            handler: { [sample] in [sample] },
            selectHandler: { throw CancellationError() }
        )
        let store = GoogleCalendarPickerStore(client: stub, tokenProvider: { "tok" })
        await store.load()
        #expect(store.phase == .ready)
        let saved = await store.select(sample)
        #expect(saved == false)
        #expect(store.phase == .ready)
    }
}
