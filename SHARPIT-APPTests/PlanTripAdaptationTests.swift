import Foundation
import Testing
@testable import Sharpit

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func day(_ value: Int, month: Int = 11) -> Date {
    paris.date(from: DateComponents(year: 2026, month: month, day: value, hour: 12))!
}

private func trip(
    from start: Int,
    to end: Int,
    constraint: TravelTrainingConstraint = .reduced,
    sports: [String]? = nil,
    type: CoachMemoryType = .travel
) -> CreateCoachMemoryInput {
    CreateCoachMemoryInput(
        type: type, label: type == .travel ? nil : "Boulot", locationLabel: type == .travel ? "Lyon" : nil,
        startDate: day(start), endDate: day(end), note: nil,
        trainingConstraint: constraint, allowedDisciplines: sports
    )
}

private func session(on date: Int, completed: Bool? = nil) -> V1PlannedSessionItem {
    V1PlannedSessionItem(id: "s\(date)", date: day(date), title: "Seuil", type: "RUN", durationMin: 55, completed: completed)
}

private let today = day(5)

@Test func aLighterTripOverASessionOffersTheAdapter() {
    let offer = PlanTripAdaptation.offer(for: trip(from: 7, to: 8), sessions: [session(on: 8)], now: today, calendar: paris)
    #expect(offer != nil)
}

@Test func aTripThatChangesNothingLeavesThePlanAlone() {
    let offer = PlanTripAdaptation.offer(
        for: trip(from: 7, to: 8, constraint: .full), sessions: [session(on: 7)], now: today, calendar: paris
    )
    #expect(offer == nil)
}

@Test func narrowedSportsAtTheUsualLoadStillNeedALook() {
    let offer = PlanTripAdaptation.offer(
        for: trip(from: 7, to: 7, constraint: .full, sports: ["RUN"]), sessions: [session(on: 7)], now: today, calendar: paris
    )
    #expect(offer != nil)
}

@Test func noSessionToDoOnThoseDaysOffersNothing() {
    let sessions = [session(on: 6), session(on: 7, completed: true), session(on: 9)]
    #expect(PlanTripAdaptation.offer(for: trip(from: 7, to: 8), sessions: sessions, now: today, calendar: paris) == nil)
}

@Test func aTripPastTheAdaptersTwoWeeksOffersNothing() {
    let offer = PlanTripAdaptation.offer(
        for: trip(from: 25, to: 26), sessions: [session(on: 25)], now: today, calendar: paris
    )
    #expect(offer == nil)
}

@Test func injuriesAndNotesAreNotTrips() {
    let offer = PlanTripAdaptation.offer(
        for: trip(from: 7, to: 8, type: .injury), sessions: [session(on: 7)], now: today, calendar: paris
    )
    #expect(offer == nil)
}

@Test func theCoachIsToldThePlaceTheDaysAndTheTraining() {
    let focus = PlanTripAdaptation(saved: trip(from: 7, to: 8, constraint: .none)).focus(calendar: paris)
    #expect(focus.contains("Lyon"))
    #expect(focus.contains("7"))
    #expect(focus.contains("8"))
    #expect(focus.contains("aucune séance"))
}
