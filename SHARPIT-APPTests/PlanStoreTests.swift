import Foundation
import Testing
@testable import Sharpit

private struct StubPlannedSessionClient: PlannedSessionServing {
    let sessions: [V1PlannedSessionItem]

    func plannedSessions(from: Date, to: Date, token: String) async throws -> [V1PlannedSessionItem] {
        sessions
    }
}

@MainActor
@Test func planStoreKeepsCalendarWhenWeekIsEmpty() async {
    let store = PlanStore(client: StubPlannedSessionClient(sessions: []), tokenProvider: { "" })
    await store.load()
    guard case .loaded(let sessions) = store.phase else {
        Issue.record("expected loaded phase with empty sessions, not a separate empty screen")
        return
    }
    #expect(sessions.isEmpty)
}

@MainActor
@Test func planFocusSessionIgnoresPastSessions() {
    let store = PlanStore(client: StubPlannedSessionClient(sessions: []), tokenProvider: { "" })
    let calendar = Calendar(identifier: .gregorian)
    let now = Date()
    let today = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

    let past = V1PlannedSessionItem(id: "past", date: yesterday, title: "Hier", type: "RUN")
    let upcoming = V1PlannedSessionItem(id: "next", date: tomorrow, title: "Demain", type: "BIKE")
    let todaySession = V1PlannedSessionItem(id: "today", date: today, title: "Aujourd'hui", type: "SWIM")

    #expect(store.focusSession(from: [past], now: now) == nil)
    #expect(store.focusSession(from: [past, upcoming], now: now)?.id == "next")
    #expect(store.focusSession(from: [upcoming, todaySession], now: now)?.id == "today")
}
