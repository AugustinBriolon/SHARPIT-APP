import Foundation
import Testing
@testable import Sharpit

private func done(_ id: String, minutes: Int, load: Double) -> PlanEntry {
    let json = #"{"id":"\#(id)","type":"RUN","date":"2026-11-10T08:00:00Z","duration":\#(minutes * 60),"load":\#(load)}"#
    let activity = try! JSONDecoder().decode(V1ActivityListItem.self, from: Data(json.utf8))
    return .executed(PlanExecutedEntry(activity: activity, plannedTitle: nil, complianceScore: nil))
}

private func session(_ id: String, minutes: Int?, load: Double?) -> V1PlannedSessionItem {
    V1PlannedSessionItem(id: id, date: Date(), type: "RUN", durationMin: minutes, load: load)
}

@Test func aWeekCountsWhatWasDoneOverWhatItHolds() {
    let totals = PlanWeekTotals([
        done("a", minutes: 60, load: 50),
        done("b", minutes: 40, load: 30),
        .planned(session("p", minutes: 90, load: 80)),
        .missed(session("m", minutes: 50, load: 40)),
    ])

    #expect(totals.doneSessions == 2)
    #expect(totals.totalSessions == 4)
    #expect(totals.missedSessions == 1)
    #expect(totals.doneMinutes == 100)
    #expect(totals.totalMinutes == 240)
    #expect(totals.doneLoad == 80)
    #expect(totals.totalLoad == 200)
    #expect(totals.sessionsFraction == 0.5)
    #expect(totals.loadFraction == 0.4)
}

@Test func aBrickIsOneSessionOfItsWholeLength() {
    let brick = PlanBrick(
        id: "b",
        legs: [session("l1", minutes: 100, load: 60), session("l2", minutes: 60, load: 40)],
        isMissed: false
    )
    let totals = PlanWeekTotals([.brick(brick)])

    #expect(totals.totalSessions == 1)
    #expect(totals.doneSessions == 0)
    #expect(totals.totalMinutes == 160)
    #expect(totals.totalLoad == 100)
}

@Test func anEmptyWeekDrawsNoArc() {
    let totals = PlanWeekTotals([])
    #expect(totals.sessionsFraction == nil)
    #expect(totals.volumeFraction == nil)
    #expect(totals.loadFraction == nil)
}

@Test func aWeekWithoutPrescribedLoadHasNoLoadRing() {
    let totals = PlanWeekTotals([.planned(session("p", minutes: 45, load: nil))])
    #expect(totals.loadFraction == nil)
    #expect(totals.volumeFraction == 0)
}

@Test func aVolumeReadsInHoursAndMinutes() {
    #expect(PlanWeekTotals.duration(minutes: 400) == "6 h 40")
    #expect(PlanWeekTotals.duration(minutes: 45) == "45 min")
    #expect(PlanWeekTotals.duration(minutes: 120) == "2 h")
    #expect(PlanWeekTotals.duration(minutes: 65) == "1 h 05")
}

@Test func aWeekIsPlacedInItsPhaseAndTheRaceCountedDown() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    calendar.firstWeekday = 2
    func monday(_ day: Int, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }
    let phases: [V1PlanPhase] = [.build, .build, .peak, .peak, .peak, .taper]
    let weeks = phases.enumerated().map { index, phase in
        V1PlanWeek(weekStart: monday(19 + index * 7, month: 10), weekIndex: index, phase: phase, targetLoad: 400)
    }
    let plan = V1TrainingPlan(id: "p", goalId: "g", raceDate: monday(21, month: 12), startDate: monday(19, month: 10), weeks: weeks)

    #expect(PlanPhaseReadout.line(plan, weekStart: monday(9), calendar: calendar) == "Spécifique · sem. 2 sur 3")
    #expect(PlanPhaseReadout.line(plan, weekStart: monday(19, month: 10), calendar: calendar) == "Développement · sem. 1 sur 2")
    #expect(PlanPhaseReadout.line(plan, weekStart: monday(4, month: 1), calendar: calendar) == nil)
    #expect(PlanPhaseReadout.line(nil, weekStart: monday(9), calendar: calendar) == nil)
    #expect(PlanPhaseReadout.countdown(plan, now: monday(14), calendar: calendar) == "course dans 37 j")
    #expect(PlanPhaseReadout.countdown(plan, now: monday(20, month: 12), calendar: calendar) == "course demain")
    #expect(PlanPhaseReadout.countdown(plan, now: monday(22, month: 12), calendar: calendar) == nil)
}
