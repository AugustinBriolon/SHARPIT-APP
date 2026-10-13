import Foundation
import Testing
@testable import Sharpit

struct GoalSeasonTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_791_878_400) // 2026-10-13

    private func day(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    private func race(
        _ title: String,
        in days: Int,
        _ priority: GoalPriority?,
        format: String? = nil,
        role: GoalRole? = nil,
        conflict: String? = nil
    ) -> V1Goal {
        V1Goal(
            id: title, title: title, kind: .race, targetDate: day(days), priority: priority, raceFormat: format,
            priorityRole: role, seasonConflict: conflict.map { V1SeasonConflict(otherGoalId: $0, otherTitle: $0) }
        )
    }

    // MARK: Role mapping

    @Test func eachLetterReadsAsItsRole() {
        #expect(GoalPriority.a.role == .primary)
        #expect(GoalPriority.b.role == .step)
        #expect(GoalPriority.c.role == .training)
        #expect(GoalRole.allCases.map(\.priority) == [.a, .b, .c])
        #expect(GoalRole.primary.label == "Objectif principal")
        #expect(GoalRole.step.label == "Course étape")
    }

    @Test func theServersRoleWinsOverTheLetter() {
        let derived = race("A", in: 30, .a)
        #expect(derived.role == .primary)
        #expect(derived.roleConsequence == GoalRole.primary.consequence)

        var told = race("B", in: 30, .a, role: .step)
        told.priorityConsequence = "Ligne du serveur"
        #expect(told.role == .step)
        #expect(told.roleConsequence == "Ligne du serveur")
        #expect(V1Goal(title: "Poids", kind: .metric, priority: .a).role == nil)
    }

    @Test func roleFieldsDecodeLenientlyAndUnknownRolesFallBack() throws {
        let json = """
        [{"id":"1","title":"Ironman","kind":"RACE","priority":"A","priorityRole":"primary",
          "priorityConsequence":"Le plan s’articule autour.","seasonConflict":{"otherGoalId":"2","otherTitle":"Tri L"}},
         {"id":"2","title":"Tri L","kind":"RACE","priority":"B","priorityRole":"mystery","seasonConflict":"oops"},
         {"id":"3","title":"Ancien","kind":"RACE","priority":"C"}]
        """
        let goals = try JSONDecoder().decode([V1Goal].self, from: Data(json.utf8))
        #expect(goals[0].priorityRole == .primary)
        #expect(goals[0].seasonConflict == V1SeasonConflict(otherGoalId: "2", otherTitle: "Tri L"))
        #expect(goals[1].priorityRole == nil)
        #expect(goals[1].role == .step)
        #expect(goals[1].seasonConflict == nil)
        #expect(goals[2].role == .training)
    }

    @Test func anEditReadsTheRoleFromTheLetterUntilTheServerAnswers() {
        let goal = race("Tri L", in: 180, .a, role: .primary, conflict: "Ironman")
        var draft = GoalDraft(goal: goal)
        draft.priority = .b
        let shown = goal.applying(draft)
        #expect(shown.role == .step)
        #expect(shown.seasonConflict == nil)
    }

    // MARK: Suggestion

    @Test func aSeasonWithoutAPrincipalMakesTheLongestRaceThePrincipal() {
        let goals = [race("Tri L", in: 180, .b, format: "Triathlon L")]
        #expect(GoalSeason.suggestedPriority(date: day(360), format: "Ironman", among: goals, now: now, calendar: calendar) == .a)
        #expect(GoalSeason.suggestedPriority(date: day(120), format: "Sprint", among: goals, now: now, calendar: calendar) == .b)
        #expect(GoalSeason.suggestedPriority(date: day(60), format: "", among: [], now: now, calendar: calendar) == .a)
    }

    @Test func aSeasonWithAPrincipalSuggestsAStep() {
        let goals = [race("Ironman", in: 360, .a, format: "XXL")]
        #expect(GoalSeason.suggestedPriority(date: day(180), format: "Triathlon L", among: goals, now: now, calendar: calendar) == .b)
        // Beyond six months, another season.
        #expect(GoalSeason.suggestedPriority(date: day(100), format: "Marathon", among: goals, now: now, calendar: calendar) == .a)
    }

    @Test func formatsRankByLength() {
        let ranks = ["Ironman", "Triathlon XL", "70.3", "Triathlon L", "Marathon", "Triathlon M", "Semi-marathon", "Sprint"]
            .map(GoalSeason.formatRank)
        #expect(ranks == ranks.sorted(by: >))
        #expect(GoalSeason.formatRank("Ironman 70.3") == GoalSeason.formatRank("70.3"))
        #expect(GoalSeason.formatRank(nil) == 0)
    }

    // MARK: Conflict

    @Test func aPrincipalWithinSixMonthsOfAnotherConflicts() {
        let goals = [race("Ironman", in: 360, .a), race("Marathon", in: 30, .a), race("Passée", in: -5, .a)]
        #expect(GoalSeason.principalConflict(date: day(200), among: goals, now: now, calendar: calendar)?.title == "Ironman")
        #expect(GoalSeason.principalConflict(date: day(100), among: goals, now: now, calendar: calendar)?.title == "Marathon")
        #expect(GoalSeason.principalConflict(date: day(360), among: goals, excluding: "Ironman", now: now, calendar: calendar) == nil)

        var draft = GoalDraft(targetDate: day(200))
        draft.priority = .b
        #expect(draft.principalConflict(among: goals) == nil)
    }

    @Test func conflictsAreListedOnceAndPassTheShorterRace() {
        let goals = [race("Ironman", in: 360, .a, format: "XXL"), race("Tri L", in: 180, .a, format: "Triathlon L")]
        let conflicts = GoalSeason.conflicts(in: goals, now: now, calendar: calendar)
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.kept.title == "Ironman")
        #expect(conflicts.first?.demoted.title == "Tri L")
    }

    @Test func theServersConflictIsTrustedOnceItSendsRoles() {
        let goals = [
            race("Ironman", in: 360, .a, role: .primary),
            race("Tri L", in: 180, .a, role: .primary),
        ]
        #expect(GoalSeason.conflicts(in: goals, now: now, calendar: calendar).isEmpty)

        let flagged = [goals[0], race("Tri L", in: 180, .a, role: .primary, conflict: "Ironman")]
        #expect(GoalSeason.conflicts(in: flagged, now: now, calendar: calendar).count == 1)
    }

    // MARK: Timeline

    @Test func stepsLeadToThePrincipalInOrderWithTheirGaps() throws {
        let goals = [
            race("Ironman", in: 360, .a),
            race("Tri L", in: 180, .b),
            race("10 km", in: 30, .c),
            race("Après", in: 400, .b),
            race("Passée", in: -10, .b),
        ]
        let timeline = try #require(GoalSeason.timeline(in: goals, now: now, calendar: calendar))
        #expect(timeline.principal.title == "Ironman")
        #expect(timeline.steps.map(\.goal.title) == ["10 km", "Tri L"])
        #expect(timeline.steps.map(\.daysToNext) == [150, 180])
    }

    @Test func withoutAPrincipalThereIsNoTimeline() {
        #expect(GoalSeason.timeline(in: [race("Tri L", in: 180, .b)], now: now, calendar: calendar) == nil)
    }

    @Test func spansReadInDaysWeeksOrMonths() {
        #expect(GoalSeason.until(days: 150) == "dans 5 mois")
        #expect(GoalSeason.until(days: 21) == "dans 3 semaines")
        #expect(GoalSeason.until(days: 4) == "dans 4 jours")
        #expect(GoalSeason.span(days: 1) == "1 jour")
    }
}
