import Foundation
import Testing
@testable import Sharpit

// Activité reads its history page by page and lays it out by month, so years of sessions never
// load or render at once.

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func day(_ iso: String) -> Date { TrainingDayId.date(iso)! }

@Test func theHistoryIsCutIntoWeeksNamedByTheirMonday() {
    // Friday 16 October 2026: the week runs from Monday 12.
    let weeks = ActivityHistory.weeks([
        V1ActivityListItem(id: "a", date: day("2026-10-13"), duration: 3600),
        V1ActivityListItem(id: "b", date: day("2025-10-13"), duration: 1800),
        V1ActivityListItem(id: "c", date: day("2026-10-12"), duration: 1200),
        V1ActivityListItem(id: "d", date: day("2026-10-11"), duration: 600),
    ], now: day("2026-10-16"), calendar: paris)

    #expect(weeks.map(\.id) == ["2026-10-12", "2026-10-05", "2025-10-13"])
    #expect(weeks.map(\.title) == ["Cette semaine", "Semaine du 5 octobre", "Semaine du 13 octobre 2025"])
    #expect(weeks[0].summary == "2 séances · 1 h 20")
    #expect(weeks[1].summary == "1 séance · 10 min")
}

@Test func aSessionOffPlanReadsAsFree() {
    let free = V1ActivityListItem(id: "a", date: day("2026-10-13"), duration: 3480, load: 72)
    #expect(ActivityRowReadout.standing(free).word == "Libre")
    #expect(ActivityRowReadout.standing(free).status == .unknown)
    // Linked to its plan with no reading: done, never « Prévue ». With one, the coach's verdict.
    let linked = V1ActivityListItem(id: "b", date: day("2026-10-13"), plannedSession: .init(id: "p", title: "Endurance", analysis: nil))
    #expect(ActivityRowReadout.standing(linked).word == "Faite")
    #expect(ActivityRowReadout.standing(linked).status == .good)
    #expect(ActivitySheetReadout.status(.harder) == .watch)
    #expect(ActivitySheetReadout.status(.asPlanned) == .good)
    #expect(ActivitySheetReadout.title(sport: "Course", title: "Tempo 3 × 10 min") == "Course · Tempo 3 × 10 min")
    #expect(ActivitySheetReadout.title(sport: "Course", title: "Course du matin") == "Course du matin")
    #expect(ActivitySheetReadout.title(sport: "Course", title: nil) == "Course")
    #expect(ActivitySheetReadout.variation(-6.4) == "−6 %")
    #expect(ActivitySheetReadout.variation(0.2) == "=")
    #expect(ActivitySheetReadout.feedback(rpe: 7, feeling: SessionFeeling(rawValue: 4)) == "7/10 · 4/5")
    #expect(ActivitySheetReadout.feedback(rpe: nil, feeling: nil) == "Noter")
}

@Test func aNewPageJoinsTheListOnceAndInOrder() {
    let loaded = [V1ActivityListItem(id: "a", date: day("2026-10-13")), V1ActivityListItem(id: "b", date: day("2026-09-01"))]
    let page = [V1ActivityListItem(id: "b", date: day("2026-09-01")), V1ActivityListItem(id: "c", date: day("2026-08-01"))]

    #expect(ActivityHistory.merge(loaded, with: page).map(\.id) == ["a", "b", "c"])
}

private struct WindowStub: ActivityServing {
    let all: [V1ActivityListItem]
    func activities(token _: String) async throws -> [V1ActivityListItem] { all }
    func activity(id _: String, token _: String) async throws -> V1ActivityDetail { throw SharpitAPIError.server }
    func activityStream(id _: String, token _: String) async throws -> V1ActivityStreamPayload { throw SharpitAPIError.server }
    func generateNarrative(id _: String, token _: String) async throws -> V1ActivityDetail { throw SharpitAPIError.server }
    func updateSubjective(id _: String, rpe _: Double?, feeling _: String?, token _: String) async throws {}
}

@Test func aWindowKeepsItsFirstDayAndLeavesItsEnd() async throws {
    // A plan week reads Monday 12 up to, not including, Monday 19.
    let stub = WindowStub(all: [
        V1ActivityListItem(id: "mon", date: day("2026-10-12")),
        V1ActivityListItem(id: "sun", date: day("2026-10-18")),
        V1ActivityListItem(id: "next", date: day("2026-10-19")),
        V1ActivityListItem(id: "before", date: day("2026-10-11")),
    ])

    let week = try await stub.activities(from: day("2026-10-12"), to: day("2026-10-19"), token: "")

    #expect(week.map(\.id) == ["mon", "sun"])
}
