import Foundation
import Testing
@testable import Sharpit

private struct StubPlannedSessionClient: PlannedSessionServing {
    let sessions: [V1PlannedSessionItem]

    func plannedSessions(from: Date, to: Date, token: String) async throws -> [V1PlannedSessionItem] {
        sessions
    }
}

private struct StubActivityClient: ActivityServing {
    var activities: [V1ActivityListItem] = []

    func activities(token: String) async throws -> [V1ActivityListItem] { activities }

    func activity(id: String, token: String) async throws -> V1ActivityDetail {
        throw SharpitAPIError.server
    }

    func activityStream(id: String, token: String) async throws -> V1ActivityStreamPayload {
        throw SharpitAPIError.server
    }

    func generateNarrative(id: String, token: String) async throws -> V1ActivityDetail {
        throw SharpitAPIError.server
    }

    func updateSubjective(id: String, rpe: Double?, feeling: String?, token: String) async throws {}
}

private func store(
    planned: [V1PlannedSessionItem] = [],
    activities: [V1ActivityListItem] = []
) -> PlanStore {
    PlanStore(
        client: StubPlannedSessionClient(sessions: planned),
        activityClient: StubActivityClient(activities: activities),
        tokenProvider: { "" }
    )
}

@MainActor
@Test func planStoreKeepsCalendarWhenWeekIsEmpty() async {
    let planStore = store()
    await planStore.load()
    guard case .loaded(let entries) = planStore.phase else {
        Issue.record("expected loaded phase with empty entries, not a separate empty screen")
        return
    }
    #expect(entries.isEmpty)
}

@MainActor
@Test func planFocusSessionIgnoresPastAndDoneSessions() {
    let planStore = store()
    let calendar = Calendar(identifier: .gregorian)
    let now = Date()
    let today = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

    let past = PlanEntry.missed(
        V1PlannedSessionItem(id: "past", date: yesterday, title: "Hier", type: "RUN")
    )
    let upcoming = PlanEntry.planned(
        V1PlannedSessionItem(id: "next", date: tomorrow, title: "Demain", type: "BIKE")
    )
    let todaySession = PlanEntry.planned(
        V1PlannedSessionItem(id: "today", date: today, title: "Aujourd'hui", type: "SWIM")
    )

    #expect(planStore.focusSession(from: [past], now: now) == nil)
    #expect(planStore.focusSession(from: [past, upcoming], now: now)?.id == "next")
    #expect(planStore.focusSession(from: [upcoming, todaySession], now: now)?.id == "today")
}

@MainActor
@Test func theStripSpansThreeWeeksAroundTheVisibleOne() {
    let planStore = store()

    #expect(planStore.stripDays.count == 21)
    #expect(planStore.stripDays.filter { planStore.isInVisibleWeek($0) }.count == 7)
    #expect(planStore.stripDays.first! < planStore.weekStart)
    #expect(planStore.stripDays.last! > planStore.weekStart)
}
