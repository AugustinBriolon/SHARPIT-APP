import Foundation
import os
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

private let googleCalendarPickerSample = V1GoogleCalendar(
    id: "cal-1", summary: "Sport", primary: false, isTarget: true
)

@Suite
struct GoogleCalendarPickerStoreTests {
    @Test @MainActor func cancelledReloadKeepsReadyWithCachedCalendars() async {
        let sample = googleCalendarPickerSample
        let counter = OSAllocatedUnfairLock(initialState: 0)
        let stub = GoogleCalendarsLoadStub {
            let n = counter.withLock { value -> Int in
                value += 1
                return value
            }
            if n == 1 { return [sample] }
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

    @Test @MainActor func urlCancelledReloadKeepsReadyWithCachedCalendars() async {
        let sample = googleCalendarPickerSample
        let counter = OSAllocatedUnfairLock(initialState: 0)
        let stub = GoogleCalendarsLoadStub {
            let n = counter.withLock { value -> Int in
                value += 1
                return value
            }
            if n == 1 { return [sample] }
            throw URLError(.cancelled)
        }
        let store = GoogleCalendarPickerStore(client: stub, tokenProvider: { "tok" })
        await store.load()
        #expect(store.phase == .ready)
        await store.load()
        #expect(store.phase == .ready)
        #expect(store.calendars == [sample])
    }

    @Test @MainActor func cancelledSelectRestoresReadyAndReturnsFalse() async {
        let sample = googleCalendarPickerSample
        let stub = GoogleCalendarsLoadStub(
            handler: { [sample] },
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
