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

// MARK: - Paging

@MainActor
@Test func theStoreStartsOnTheCurrentWeek() {
    let planStore = store()

    #expect(planStore.selectedOffset == 0)
    #expect(planStore.isCurrentWeek)
    #expect(planStore.weekDays.count == 7)
}

@MainActor
@Test func weekOffsetsMoveInWholeWeeks() {
    let planStore = store()
    let calendar = Calendar(identifier: .gregorian)

    let now = planStore.weekStart(forOffset: 0)
    let next = planStore.weekStart(forOffset: 1)
    let previous = planStore.weekStart(forOffset: -1)

    #expect(calendar.dateComponents([.day], from: now, to: next).day == 7)
    #expect(calendar.dateComponents([.day], from: previous, to: now).day == 7)
}

@MainActor
@Test func weeksStartOnMonday() {
    let planStore = store()
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2

    for offset in [-3, 0, 5] {
        // ISO weekday 2 == Monday in the Gregorian calendar's numbering.
        #expect(calendar.component(.weekday, from: planStore.weekStart(forOffset: offset)) == 2)
    }
}

@MainActor
@Test func aDayResolvesToTheOffsetOfItsWeek() {
    let planStore = store()

    for offset in [-4, -1, 0, 1, 7] {
        for day in planStore.weekDays(forOffset: offset) {
            #expect(planStore.offset(forWeekContaining: day) == offset)
        }
    }
}

@MainActor
@Test func pickingADateSelectsItsWeek() {
    let planStore = store()
    let target = planStore.weekDays(forOffset: 3)[4]

    planStore.showWeek(containing: target)

    #expect(planStore.selectedOffset == 3)
}

@MainActor
@Test func theOffsetIsClampedToThePagersRange() {
    let planStore = store()
    let calendar = Calendar(identifier: .gregorian)
    let farAway = calendar.date(byAdding: .year, value: 5, to: Date())!

    #expect(planStore.offset(forWeekContaining: farAway) == PlanStore.offsets.upperBound)
    #expect(
        planStore.offset(forWeekContaining: calendar.date(byAdding: .year, value: -5, to: Date())!)
            == PlanStore.offsets.lowerBound
    )
}

@MainActor
@Test func goingToTodayReturnsToTheCurrentWeek() {
    let planStore = store()
    planStore.selectedOffset = 6

    planStore.goToToday()

    #expect(planStore.selectedOffset == 0)
    #expect(planStore.isCurrentWeek)
}

@MainActor
@Test func theCalendarMayPickAnyWeekThePagerHolds() {
    let planStore = store()
    let range = planStore.selectableDates

    #expect(range.contains(planStore.weekStart(forOffset: PlanStore.offsets.lowerBound)))
    #expect(range.contains(planStore.weekDays(forOffset: PlanStore.offsets.upperBound).last!))
}

@MainActor
@Test func loadingASelectionFillsItAndItsNeighboursOnly() async {
    let planStore = store()
    planStore.selectedOffset = 2

    await planStore.loadAroundSelection()

    for offset in [1, 2, 3] {
        guard case .loaded = planStore.phase(forOffset: offset) else {
            Issue.record("expected week \(offset) to be loaded")
            return
        }
    }
    guard case .loading = planStore.phase(forOffset: 5) else {
        Issue.record("a distant week must not load until it is near")
        return
    }
}

@MainActor
@Test func aLoadedWeekIsNotFetchedAgainUnlessForced() async {
    let counter = LoadCounter()
    let planStore = PlanStore(
        client: CountingPlannedSessionClient(counter: counter),
        activityClient: StubActivityClient(),
        tokenProvider: { "" }
    )

    await planStore.load(offset: 0)
    await planStore.load(offset: 0)
    #expect(await counter.value == 1)

    await planStore.load(offset: 0, force: true)
    #expect(await counter.value == 2)
}

// MARK: - Day status

@MainActor
@Test func theStripReadsNothingUntilItsWeekHasLoaded() {
    let planStore = store()

    #expect(planStore.status(on: planStore.weekDays[0]) == nil)
}

@Test func aDayWithSomethingDoneReadsAsDoneEvenIfAnotherSessionWasMissed() {
    let missed = PlanEntry.missed(V1PlannedSessionItem(id: "m", date: Date(), type: "RUN"))
    let done = try! JSONDecoder().decode(
        V1ActivityListItem.self,
        from: Data(#"{"id":"a","type":"RUN","date":"2026-09-14T08:00:00Z"}"#.utf8)
    )
    let executed = PlanEntry.executed(
        PlanExecutedEntry(activity: done, plannedTitle: nil, complianceScore: nil)
    )

    #expect(PlanDayStatus.status(of: [missed, executed]) == .executed)
}

@Test func aDayWithOnlyAPrescriptionAheadReadsAsPlanned() {
    let planned = PlanEntry.planned(V1PlannedSessionItem(id: "p", date: Date(), type: "RUN"))

    #expect(PlanDayStatus.status(of: [planned]) == .planned)
}

@Test func aDayWithOnlyAMissedPrescriptionReadsAsMissed() {
    let missed = PlanEntry.missed(V1PlannedSessionItem(id: "m", date: Date(), type: "RUN"))

    #expect(PlanDayStatus.status(of: [missed]) == .missed)
}

@Test func aDayWithNothingHasNoStatus() {
    #expect(PlanDayStatus.status(of: []) == nil)
}

// MARK: - Support

private actor LoadCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct CountingPlannedSessionClient: PlannedSessionServing {
    let counter: LoadCounter

    func plannedSessions(from: Date, to: Date, token: String) async throws -> [V1PlannedSessionItem] {
        await counter.increment()
        return []
    }
}
