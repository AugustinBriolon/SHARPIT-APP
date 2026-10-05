import Foundation
import Testing
@testable import Sharpit

// MARK: - Goal edit

private func race() -> V1Goal {
    V1Goal(
        id: "g1",
        title: "Marathon de Paris",
        kind: .race,
        targetDate: TrainingDayId.date("2027-04-11")!,
        location: "Paris",
        priority: .a,
        raceFormat: "Marathon",
        targetPerformance: "3h30"
    )
}

@Test func anUntouchedGoalSendsNothing() {
    let draft = GoalDraft(goal: race())
    #expect(draft.changes(from: draft).isEmpty)
}

@Test func movingARaceSendsItsDayAlone() throws {
    let original = GoalDraft(goal: race())
    var draft = original
    draft.targetDate = TrainingDayId.date("2027-04-18")!

    let fields = draft.changes(from: original)
    #expect(fields.keys.sorted() == ["targetDate"])
    let sent = try #require(fields["targetDate"]?.string)
    #expect(TrainingDayId.today(now: try Date.fromAPI(sent)) == "2027-04-18")
}

@Test func clearingAFieldSendsNull() {
    let original = GoalDraft(goal: race())
    var draft = original
    draft.targetPerformance = "  "
    draft.priority = .b
    let fields = draft.changes(from: original)
    #expect(fields["targetPerformance"] == .null)
    #expect(fields["priority"] == .string("B"))
}

@Test func aMetricMayLoseItsDate() {
    let goal = V1Goal(id: "g2", title: "FTP", kind: .metric, targetValue: 300, unit: "W", targetDate: .now)
    let original = GoalDraft(goal: goal)
    var draft = original
    draft.hasTargetDate = false
    draft.targetValueText = "310,5"
    let fields = draft.changes(from: original)
    #expect(fields["targetDate"] == .null)
    #expect(fields["targetValue"] == .number(310.5))
}

@Test func aGoalNeedsANameAndNumbers() {
    var draft = GoalDraft.new()
    #expect(draft.missingRequirement != nil)
    draft.title = "FTP"
    #expect(draft.missingRequirement == nil)
    draft.targetValueText = "trois cents"
    #expect(draft.missingRequirement == "La valeur cible n’est pas un nombre.")
}

@Test func anEditShowsBeforeTheServerAnswers() {
    var draft = GoalDraft(goal: race())
    draft.title = "Marathon de Lyon"
    draft.location = ""
    let shown = race().applying(draft)
    #expect(shown.title == "Marathon de Lyon")
    #expect(shown.location == nil)
    #expect(shown.raceFormat == "Marathon")
}

// MARK: - History filters

private let now = TrainingDayId.date("2026-10-05")!

private let history: [V1ActivityListItem] = [
    V1ActivityListItem(id: "a", type: .run, date: now, title: "Footing du matin"),
    V1ActivityListItem(id: "b", type: .bike, date: TrainingDayId.date("2026-09-20")!, title: "Sortie longue"),
    V1ActivityListItem(id: "c", type: .run, date: TrainingDayId.date("2026-03-01")!, title: "Fractionné"),
]

@Test func noFilterShowsTheWholeHistory() {
    #expect(ActivityFilter().apply(to: history, now: now).count == 3)
    #expect(!ActivityFilter().isActive)
}

@Test func aSportAndAPeriodNarrowTheHistory() {
    var filter = ActivityFilter()
    filter.sport = .run
    #expect(filter.apply(to: history, now: now).map(\.id) == ["a", "c"])
    filter.period = .month
    #expect(filter.apply(to: history, now: now).map(\.id) == ["a"])
    #expect(filter.narrows)
}

@Test func theSearchIgnoresCaseAndAccents() {
    var filter = ActivityFilter()
    filter.query = "fractionne"
    #expect(filter.apply(to: history, now: now).map(\.id) == ["c"])
    filter.query = "vélo"
    #expect(filter.apply(to: history, now: now).map(\.id) == ["b"])
}

@Test func theMenuOffersOnlyTheSportsDoneMostFirst() {
    #expect(ActivityFilter.sports(in: history) == [.run, .bike])
}
