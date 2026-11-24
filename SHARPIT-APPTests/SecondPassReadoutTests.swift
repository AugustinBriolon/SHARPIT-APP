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

@Test func aScaleReadsTheStepUnderTheFinger() {
    #expect(CliniqueScaleReadout.step(at: 0, width: 300, count: 10) == 0)
    #expect(CliniqueScaleReadout.step(at: 199, width: 300, count: 10) == 6)
    #expect(CliniqueScaleReadout.step(at: 300, width: 300, count: 10) == 9)
    #expect(CliniqueScaleReadout.step(at: -40, width: 300, count: 5) == 0)
    #expect(CliniqueScaleReadout.step(at: 900, width: 300, count: 5) == 4)
    #expect(CliniqueScaleReadout.step(at: 10, width: 0, count: 5) == 0)
}

@Test func aScaleSaysItsAnswerInFiguresAndWords() {
    #expect(CliniqueScaleReadout.answer(7, outOf: 10, word: SessionEffortReadout.word(7)) == "7 / 10 · Dur")
    #expect(CliniqueScaleReadout.answer(4, outOf: 5, word: nil) == "4 / 5")
    #expect(CliniqueScaleReadout.answer(nil, outOf: 5, word: nil) == "À noter")
    #expect((1...10).allSatisfy { SessionEffortReadout.word($0) != nil })
    #expect(SessionEffortReadout.word(11) == nil)
    #expect(WellnessReadout.ends(.energy) == ("Épuisé", "Plein"))
}

@Test func tonightsNeedIsCutByWhatAddsToIt() {
    let parts = SleepSheetReadout.needParts(
        need: 500, contributors: V1SleepNeededContributors(debtBoostMin: 20, strainBoostMin: 0, efficiencyBoostMin: 10)
    )
    #expect(parts.map(\.minutes) == [470, 20, 10])
    #expect(parts.map(\.label) == ["habituel 7 h 50", "dette +20 min", "efficacité +10 min"])
    #expect(SleepSheetReadout.needParts(need: 450, contributors: nil).map(\.minutes) == [450])
}

@Test func theSleepBankDrawsEachNightAgainstTheNeed() {
    let history = [
        V1SleepNight(date: "2026-11-09", minutes: 400), V1SleepNight(date: "2026-11-10", minutes: nil),
        V1SleepNight(date: "2026-11-11", minutes: 480),
    ]
    let gaps = SleepSheetReadout.gaps(history, targetMin: 450)
    #expect(gaps.map(\.minutes) == [-50, 30])
    #expect(gaps.map(\.id) == ["2026-11-09", "2026-11-11"])
    #expect(SleepSheetReadout.dayInitial("nope") == "")
}

@Test func aSessionIsOnlyLinkedToARaceStillToRun() {
    let day = Date(timeIntervalSince1970: 1_794_000_000)
    func race(_ id: String, _ offsetDays: Double?) -> V1Goal {
        V1Goal(id: id, title: id, kind: .race, targetDate: offsetDays.map { day.addingTimeInterval($0 * 86_400) })
    }
    let goals = [race("past", -30), race("soon", 3), race("undated", nil), race("linked-past", -60)]
    #expect(ActivityGoalCandidates.ordered(goals, around: day).map(\.id) == ["soon", "undated"])
    #expect(ActivityGoalCandidates.ordered(goals, around: day, linked: "linked-past").map(\.id) == ["soon", "linked-past", "undated"])
}

@Test func aSessionWithoutMovesHasNoRoutinesDrawer() {
    #expect(SessionRoutinesReadout.hasMoves(nil) == false)
    #expect(SessionRoutinesReadout.hasMoves(PlannedSessionPreview.demo.routines))
}

private func history(_ name: String, weight: Double? = 60, duration: Int? = nil, best: V1StrengthExercise.Best = .init()) -> V1StrengthExercise {
    V1StrengthExercise(
        name: name, last: .init(date: "2026-11-10", sets: 4, reps: duration == nil ? 8 : 1, weightKg: weight, durationSec: duration),
        best: best
    )
}

@Test func anExercisesHistoryReadsItsLastSessionAndItsBest() {
    let bench = history("Développé couché", best: .init(weightKg: 70, reps: 5))
    #expect(StrengthHistoryReadout.line(bench) == "Dernière fois 4 × 8 · 60 kg · Meilleur 70 kg × 5")
    let plank = history("Gainage", weight: nil, duration: 45, best: .init(durationSec: 90))
    #expect(StrengthHistoryReadout.line(plank) == "Dernière fois 4 × 45 s · Meilleur 1 min 30 s")
    #expect(StrengthHistoryReadout.best(history("Pompes", weight: nil)) == nil)
    #expect(bench.id == history("developpe  COUCHE").id)
}

@Test func aSetOpensOnTheLastLoadOnlyWhereThePlanGivesNone() {
    var session = GuidedStrengthSession.logging(title: "Libre", exercises: [])
    session.addExercise(name: "Squat")
    session.addExercise(name: "Développé couché", history: history("Développé couché", weight: 55))
    session.applyHistory([history("Squat", weight: 80), history("Développé couché", weight: 90)])
    let squat = session.targets.filter { $0.exerciseName == "Squat" }
    #expect(squat.count == 3)
    #expect(squat.allSatisfy { $0.loggedWeightKg == 80 })
    // Added from its history, the exercise already carries a figure: it is kept.
    #expect(session.targets.filter { $0.exerciseName == "Développé couché" }.allSatisfy { $0.loggedWeightKg == 55 })
}

@Test func anExerciseAddedTwiceGetsOneMoreSetNotASecondBlock() {
    var session = GuidedStrengthSession.logging(title: "Libre", exercises: [])
    session.addExercise(name: "Tractions")
    session.addExercise(name: " tractions ")
    #expect(session.exerciseGroups.map(\.name) == ["Tractions"])
    #expect(session.targets.count == 4)
    session.addExercise(name: "   ")
    #expect(session.targets.count == 4)
}

@Test func aLoggedSessionReopensOnItsExercisesAndHandsThemBack() {
    let written = [
        StrengthExerciseDraft(name: "Squat", sets: 3, reps: 8, weightKg: 80),
        StrengthExerciseDraft(name: "Étirement psoas", sets: 2, reps: 0, durationSec: 30, notes: "Zone travaillée : Hanches et fessiers"),
    ]
    let session = GuidedStrengthSession.logging(title: "Libre", exercises: written)
    #expect(session.completedCount == 5)
    let back = session.activityExercises()
    #expect(back.map(\.name) == ["Squat", "Étirement psoas"])
    #expect(back.map(\.sets) == [3, 2])
    #expect(back[0].weightKg == 80)
    #expect(back[1].durationSec == 30)
    #expect(back[1].notes == "Zone travaillée : Hanches et fessiers")
}

@Test func theExerciseSearchPutsTheAthletesOwnFirstAndOffersToCreate() {
    let library = [history("Développé couché"), history("Squat bulgare")]
    #expect(ExercisePickerReadout.results(query: "", library: library).own.count == 2)
    let found = ExercisePickerReadout.results(query: "squat", library: library)
    #expect(found.own.map(\.name) == ["Squat bulgare"])
    #expect(found.creatable == "squat")
    #expect(ExercisePickerReadout.results(query: "Squat Bulgare", library: library).creatable == nil)
    #expect(ExercisePickerReadout.results(query: "x", library: library).creatable == nil)
    #expect(ExercisePickerReadout.zoneNote("Tronc") == "Zone travaillée : Tronc")
}

@Test func theCatalogIsBrowsedFromAToZWhateverTheCaseOrTheAccents() {
    func entry(_ name: String) -> ExerciseMediaCatalog.Entry { .init(id: name, name: name) }
    let sections = ExercisePickerReadout.sections([
        entry("Squat"), entry("élévation latérale"), entry("Abdos"), entry("3/4 sit-up"), entry("Écarté"), entry("air bike"),
    ])
    // No empty letter, figures after Z.
    #expect(sections.map(\.title) == ["A", "E", "S", "#"])
    #expect(sections[0].entries.map(\.name) == ["Abdos", "air bike"])
    #expect(sections[1].entries.map(\.name) == ["Écarté", "élévation latérale"])
    #expect(ExercisePickerReadout.indexTitles(hasOwn: true, sections: sections) == ["★", "A", "E", "S", "#"])
    #expect(ExercisePickerReadout.indexTitles(hasOwn: false, sections: sections) == ["A", "E", "S", "#"])
}

@Test func theWholeCatalogIsListedOnceWhenNothingIsTyped() {
    #expect(ExercisePickerReadout.results(query: " ", library: []).isBrowsing)
    #expect(!ExercisePickerReadout.results(query: "squat", library: []).isBrowsing)
    let listed = ExercisePickerReadout.browseSections.flatMap(\.entries)
    #expect(listed.count > 1_000)
    #expect(Set(listed.map(\.id)).count == listed.count)
}

@Test func theIndexGivesTheLetterUnderTheFinger() {
    let titles = ["★", "A", "B", "C"]
    #expect(ExercisePickerReadout.indexTitle(at: 0, in: titles) == "★")
    #expect(ExercisePickerReadout.indexTitle(at: 0.3, in: titles) == "A")
    #expect(ExercisePickerReadout.indexTitle(at: 0.99, in: titles) == "C")
    // A finger slid past either end holds the first or the last letter.
    #expect(ExercisePickerReadout.indexTitle(at: -0.4, in: titles) == "★")
    #expect(ExercisePickerReadout.indexTitle(at: 1.7, in: titles) == "C")
    #expect(ExercisePickerReadout.indexTitle(at: 0.5, in: []) == nil)
}

@Test func aSessionLeftUnsavedComesBackAsTyped() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "draft-\(UUID().uuidString).json")
    let store = ActivityDraftLocalStore(fileURL: url)
    var draft = ActivityDraft(date: Date(timeIntervalSince1970: 1_794_000_000))
    draft.sport = .strength
    draft.title = "Haut du corps"
    draft.rpe = 7
    draft.exercises = [StrengthExerciseDraft(name: "Tractions", sets: 4, reps: 6, notes: "Zone travaillée : Dos")]
    store.save(draft.snapshot)
    let back = try #require(store.load().flatMap(ActivityDraft.init(snapshot:)))
    #expect(back.title == "Haut du corps")
    #expect(back.sport == .strength)
    #expect(back.rpe == 7)
    #expect(back.exercises.map(\.name) == ["Tractions"])
    #expect(back.exercises.first?.notes == "Zone travaillée : Dos")
    store.erase()
    #expect(store.load() == nil)
}

@Test func anExerciseSaysWhereItStandsInTheSession() {
    #expect(GuidedStrengthReadout.standing(done: 0, total: 4) == nil)
    #expect(GuidedStrengthReadout.standing(done: 2, total: 4)?.label == "En cours")
    #expect(GuidedStrengthReadout.standing(done: 4, total: 4)?.label == "Terminé")
    #expect(GuidedStrengthReadout.finishTitle(done: 0, isLogging: true) == "Aucune série encore")
    #expect(GuidedStrengthReadout.finishTitle(done: 2, isLogging: true) == "Valider les exercices")
    #expect(GuidedStrengthReadout.finishTitle(done: 2, isLogging: false) == "Terminer la séance")
}
