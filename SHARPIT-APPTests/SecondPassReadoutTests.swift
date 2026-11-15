import Foundation
import Testing
import UIKit
@testable import Sharpit

private func result(_ key: String, _ value: Double, low: Double?, high: Double?) -> V1BloodTest.Result {
    V1BloodTest.Result(markerKey: key, value: value, unit: "", refLow: low, refHigh: high)
}

@Test func santeListsTheBiomarkersOutOfRangeFirst() {
    let results = [
        result("a", 5, low: 1, high: 10),
        result("b", 12, low: 1, high: 10),
        result("c", 5, low: 1, high: 10),
        result("d", 0.5, low: 1, high: 10),
        result("e", 5, low: 1, high: 10),
        result("f", 5, low: 1, high: 10),
    ]
    #expect(SanteReadout.leading(results).map(\.markerKey) == ["b", "d", "a", "c", "e"])
    #expect(SanteReadout.leading(Array(results.prefix(2))).count == 2)
}

private func week(_ start: Date, _ index: Int, _ phase: V1PlanPhase, load: Double = 400) -> V1PlanWeek {
    V1PlanWeek(weekStart: start, weekIndex: index, phase: phase, targetLoad: load)
}

@Test func theMacroPlanGathersItsWeeksByPhaseAndMarksTheCurrentOne() {
    let now = Date(timeIntervalSince1970: 1_794_700_800) // mid-November 2026
    let day: TimeInterval = 86_400
    let weeks = [
        week(now.addingTimeInterval(-14 * day), 0, .base),
        week(now.addingTimeInterval(-7 * day), 1, .base),
        week(now, 2, .build),
        week(now.addingTimeInterval(7 * day), 3, .build),
        week(now.addingTimeInterval(14 * day), 4, .taper),
    ]
    let runs = MacroPlanReadout.runs(weeks, now: now)
    #expect(runs.map(\.phase) == [.base, .build, .taper])
    #expect(runs.map(\.weeks.count) == [2, 2, 1])
    #expect(runs.map(\.isCurrent) == [false, true, false])
    #expect(MacroPlanReadout.standing(weeks, now: now) == "Semaine 3 sur 5")
    #expect(MacroPlanReadout.standing(weeks, now: now.addingTimeInterval(90 * day)) == "5 semaines")
}

@Test func planWordsItsTripsAndItsGeneratorSpans() {
    #expect(PlanAroundReadout.trips(0) == nil)
    #expect(PlanAroundReadout.trips(1) == "1 déclaré")
    #expect(PlanAroundReadout.trips(3) == "3 déclarés")
    #expect(PlanGeneratorReadout.span(3) == "3 jours")
    #expect(PlanGeneratorReadout.span(7) == "1 semaine")
    #expect(PlanGeneratorReadout.span(14) == "2 semaines")
}

@Test func santeSharesOnlyTheCardsItCanFill() {
    let empty = V1HealthOverview(synthesis: V1HealthSynthesis(normed: 0, inNorm: 0))
    #expect(SanteShareCard.available(for: empty).isEmpty)
    let normed = V1HealthOverview(synthesis: V1HealthSynthesis(normed: 7, inNorm: 6))
    #expect(SanteShareCard.available(for: normed) == [.summary])
}

@Test func aPageTakesNoTouchWhileABackSwipeIsUnderWay() {
    #expect(!BackSwipeTouches.allowed(during: .began))
    #expect(!BackSwipeTouches.allowed(during: .changed))
    #expect(BackSwipeTouches.allowed(during: .ended))
    #expect(BackSwipeTouches.allowed(during: .cancelled))
    #expect(BackSwipeTouches.allowed(during: .possible))
}

@Test func aMarkerSheetSumsUpItsMonthAndItsTarget() {
    #expect(CorpsFormat.summary(trend: "− 0,6 kg sur le mois", target: "71,0 kg") == "− 0,6 kg sur le mois · visé 71,0 kg")
    #expect(CorpsFormat.summary(trend: nil, target: "71,0 kg") == "visé 71,0 kg")
    #expect(CorpsFormat.summary(trend: nil, target: nil) == nil)
    #expect(BloodTestsReadout.count(1) == "1 compte rendu")
    #expect(BloodTestsReadout.count(4) == "4 comptes rendus")
}

@Test func aCoachCardKeepsItsMarksInsideTheirTracks() {
    #expect(CoachDataCardLayout.share(66) == 0.66)
    #expect(CoachDataCardLayout.share(140) == 1)
    #expect(CoachDataCardLayout.share(-3) == 0)
    #expect(CoachDataCardLayout.effortShare(10.5) == 0.5)
    #expect(CoachDataCardLayout.effortShare(30) == 1)
    #expect(CoachDataCardLayout.dayNumber("2026-11-14") == "14")
    #expect(CoachDataCardLayout.dayNumber("x") == "")
}

@Test func theJournalWordsItsAmounts() {
    let french = Locale(identifier: "fr_FR")
    #expect(JournalAmountFormat.milligrams(160) == "160 mg")
    #expect(JournalAmountFormat.volume(250, locale: french) == "25 cl")
    #expect(JournalAmountFormat.volume(0, locale: french) == "0 cl")
    #expect(JournalAmountFormat.volume(1_250, locale: french) == "1,25 L")
    #expect(JournalAmountFormat.volume(2_000, locale: french) == "2 L")
}

@Test func eachMeasuredLineHasItsOwnGlyph() {
    #expect(JournalCatalogue.symbolName(forAuto: "steps_10k") == "figure.walk")
    #expect(JournalCatalogue.symbolName(forAuto: "sleep_target") != JournalCatalogue.symbolName(forAuto: "steps_10k"))
    #expect(JournalCatalogue.symbolName(forAuto: "unknown_line") == "waveform.path.ecg")
}

@Test func routinesAreReadFromTheLinkedPlanSession() {
    let sessions = [V1PlannedSessionItem(id: "s1", date: .now, type: "RUN")]
    #expect(ActivityRoutinesReadout.routines(of: "s1", in: sessions) == nil)
    #expect(ActivityRoutinesReadout.routines(of: "missing", in: sessions) == nil)
}
