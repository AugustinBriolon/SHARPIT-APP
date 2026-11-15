import Foundation
import Testing
@testable import Sharpit

/// What unkind data must not break: a title of spaces, a sport the app has no word for, a sheet
/// the app opens by itself over one the athlete asked for.
struct WorstCaseDataTests {
    @Test func aTitleOfSpacesIsNoTitle() {
        #expect(Optional("   ").named == nil)
        #expect(Optional(" \n\t").named == nil)
        #expect(String?.none.named == nil)
        #expect(Optional("  Footing ").named == "Footing")
    }

    @Test func aSessionWithoutANameReadsAsItsSportAlone() {
        #expect(ActivitySheetReadout.title(sport: "Course", title: "   ") == "Course")
        #expect(ActivitySheetReadout.title(sport: "Course", title: nil) == "Course")
        #expect(ActivitySheetReadout.title(sport: "Course", title: "Tempo") == "Course · Tempo")
    }

    @Test func everySportHasOneFrenchName() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        func session(_ type: String?) -> V1PlannedSessionItem { V1PlannedSessionItem(id: "s", date: day, type: type) }

        // The web's words (`ACTIVITY_TYPE_LABELS`): never the raw « Other », never two names.
        #expect(session("OTHER").displayType == "Autre")
        #expect(session("other").displayType == "Autre")
        #expect(session("STRENGTH").displayType == V1ActivityType.strength.label)
        #expect(session("PILATES").displayType == "Autre")
        #expect(session(nil).displayType == "Séance")
        #expect(GoalAnalyticsEngine.sportDisplayName("STRENGTH") == V1ActivityType.strength.label)
        #expect(V1ActivityType.strength.label == "Musculation")
        #expect(V1ActivityType.other.label == "Autre")
    }
}

struct WorstCaseReadoutTests {
    @Test func aTitleTypedOnTwoLinesReadsOnOne() {
        #expect(Optional("Natation\ntechnique").named == "Natation technique")
    }

    @Test func aLengthOfTimeIsSaidOneWay() {
        #expect(SharpitFigureFormat.duration(seconds: 14 * 3_600 + 59 * 60 + 59) == "14 h 59")
        #expect(SharpitFigureFormat.duration(seconds: 45) == "45 s")
        #expect(SharpitFigureFormat.duration(seconds: 0) == "0 min")
        #expect(SharpitFigureFormat.duration(seconds: -1) == "—")
        #expect(SharpitFigureFormat.duration(seconds: .infinity) == "—")
        #expect(SharpitFigureFormat.duration(minutes: 899) == "14 h 59")
        #expect(PlannedSessionFormat.duration(899) == PlanWeekTotals.duration(minutes: 899))
        #expect(DoneBrickFormat.duration(4_800) == "1 h 20")
    }

    @Test func aFigureKeepsItsUnitWhenTheLineBreaks() {
        let line = ["Ven. 13", "128,4 km", "14 h 59"].joinedAsFacts()
        // Breakable only around the points between two facts.
        #expect(line == "Ven.\u{00A0}13 · 128,4\u{00A0}km · 14\u{00A0}h\u{00A0}59")
    }

    @Test func aGoalOfAnotherYearSaysItsYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let thisYear = calendar.date(from: DateComponents(year: 2026, month: 12, day: 6))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 10, day: 11))!

        #expect(!GoalsReadout.rowDate(thisYear, now: now, calendar: calendar).contains("2026"))
        #expect(GoalsReadout.rowDate(lastYear, now: now, calendar: calendar).contains("2025"))
    }

    @Test func gramsAreGroupedAndNeverTrap() {
        #expect(NutritionReadout.grams(71.2) == "71 g")
        #expect(NutritionReadout.grams(18_632.4) == "\(18_632.formatted(.number.locale(AppLanguage.locale))) g")
        #expect(NutritionReadout.grams(.nan) == "—")
        #expect(NutritionReadout.grams(nil) == "—")
    }

    @Test func onlyALongNoteIsCut() {
        #expect(!SharpitExpandableText.runsLong("Bonnes sensations."))
        #expect(SharpitExpandableText.runsLong(String(repeating: "Vent de face. ", count: 40)))
        #expect(SharpitExpandableText.runsLong("a\nb\nc\nd\ne\nf\ng"))
    }
}

@MainActor
struct RequestedSheetTests {
    @Test func aSheetTheAthleteAskedForIsKnownToBeUp() {
        let router = ShellRouter()
        #expect(!router.isShowingRequestedSheet)

        router.openSettings()
        #expect(router.isShowingRequestedSheet)

        router.isShowingSettings = false
        router.isShowingGoals = true
        #expect(router.isShowingRequestedSheet)
    }
}
