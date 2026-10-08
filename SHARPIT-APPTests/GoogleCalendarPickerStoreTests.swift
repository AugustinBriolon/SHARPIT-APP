import Testing
@testable import Sharpit

private struct GoogleCalendarsLoadStub: GoogleCalendarsServing {
    let handler: @Sendable () async throws -> [V1GoogleCalendar]

    func googleCalendars(token: String) async throws -> [V1GoogleCalendar] {
        try await handler()
    }

    func selectGoogleCalendar(calendarId: String, calendarName: String?, token: String) async throws {}
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

    @Test @MainActor func cancelledInitialLoadDoesNotStayLoading() async {
        let stub = GoogleCalendarsLoadStub { throw CancellationError() }
        let store = GoogleCalendarPickerStore(client: stub, tokenProvider: { "tok" })
        await store.load()
        #expect(store.phase == .ready)
        #expect(store.calendars.isEmpty)
    }
}
