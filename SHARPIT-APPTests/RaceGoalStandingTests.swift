import Foundation
import Testing
@testable import Sharpit

@Suite struct RaceGoalStandingTests {
    private let past = Date(timeIntervalSinceNow: -86_400)

    private func race(status: GoalRaceStatus?, achieved: Bool = false, result: V1GoalRaceResult? = nil) -> V1Goal {
        V1Goal(
            id: "half", title: "Half IronMan Versailles", kind: .race, targetDate: past,
            achieved: achieved, targetPerformance: "Sub 6h", status: status, result: result
        )
    }

    @Test func decodesStatusAndResult() throws {
        let json = """
        {"id":"g","title":"Half","kind":"RACE","achieved":true,"status":"done",
         "result":{"activityId":"tri","durationSec":20403}}
        """
        let goal = try JSONDecoder().decode(V1Goal.self, from: Data(json.utf8))
        #expect(goal.status == .done)
        #expect(goal.result == V1GoalRaceResult(activityId: "tri", durationSec: 20403))
    }

    @Test func unknownStatusDecodesAsNil() throws {
        let json = #"{"id":"g","title":"Half","kind":"RACE","status":"later"}"#
        #expect(try JSONDecoder().decode(V1Goal.self, from: Data(json.utf8)).status == nil)
    }

    @Test func doneRaceReadsItsTimeAgainstTheAim() {
        let goal = race(status: .done, result: V1GoalRaceResult(activityId: "tri", durationSec: 20403))
        #expect(goal.isReached)
        #expect(GoalFormat.raceCardLine(goal) == "Terminée · 5:40:03 · −19:57 vs objectif")
    }

    @Test func doneRaceWithoutAimOrTimeStaysShort() {
        var goal = race(status: .done, achieved: true)
        goal.targetPerformance = "Finir"
        #expect(GoalFormat.doneLine(goal) == "Terminée")
    }

    @Test func awaitingRaceStaysInProgressAndSaysSo() {
        let goal = race(status: .awaitingResult)
        #expect(!goal.isReached)
        #expect(GoalFormat.raceCardLine(goal) == "Ta course est passée · résultat à lier")
    }

    @Test func validationShowsDoneOnTheTap() {
        var goal = race(status: .awaitingResult)
        goal.achieved = true
        #expect(goal.raceStatus == .done)
    }

    @Test func raceDayActivitiesAreThatDaysLongestFirst() {
        let calendar = Calendar(identifier: .gregorian)
        let day = past
        let activities = [
            V1ActivityListItem(id: "short", date: day, duration: 600),
            V1ActivityListItem(id: "other-day", date: day.addingTimeInterval(-3 * 86_400), duration: 30_000),
            V1ActivityListItem(id: "tri", type: .triathlon, date: day, duration: 20_403),
        ]
        let goal = race(status: .awaitingResult)
        #expect(GoalOrdering.raceDayActivities(for: goal, in: activities, calendar: calendar).map(\.id) == ["tri", "short"])
    }

    @Test func linkingAPastRaceShowsItReachedBeforeTheServerAnswers() {
        let goal = race(status: .awaitingResult)
        #expect(V1ActivityGoal(goal: goal).achieved == true)
        var ahead = goal
        ahead.targetDate = Date(timeIntervalSinceNow: 10 * 86_400)
        #expect(V1ActivityGoal(goal: ahead).achieved == false)
    }
}
