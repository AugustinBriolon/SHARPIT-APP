import Foundation
import Testing
@testable import Sharpit

private func leg(_ kind: String, _ seconds: Double, label: String = "") -> V1MultisportLeg {
    V1MultisportLeg(
        kind: kind, label: label, durationSec: seconds, movingDurationSec: nil, distanceM: nil,
        avgHr: nil, avgSpeedMs: nil, elevationM: nil, calories: nil, transitionIndex: nil
    )
}

private let triathlonLegs = [
    leg("swim", 1_800, label: "Swim"),
    leg("transition", 120, label: "Transition"),
    leg("bike", 4_200, label: "Bike"),
    leg("transition", 60, label: "Transition"),
    leg("run", 2_820, label: "Run"),
]

private func todayJSON(race: String?) throws -> V1TodayResponse {
    var json = try #require(try JSONSerialization.jsonObject(with: fixtureData("full.json")) as? [String: Any])
    json["trainingDayId"] = "2026-10-12"
    if let race {
        json["race"] = try JSONSerialization.jsonObject(with: Data(race.utf8))
    }
    return try JSONDecoder().decode(V1TodayResponse.self, from: JSONSerialization.data(withJSONObject: json))
}

// MARK: - Legs timeline

@Test func legsAreLabelledInRaceOrderAndShareTheWhole() {
    let segments = RaceLegsTimeline.segments(triathlonLegs)
    #expect(segments.map(\.label) == ["Natation", "T1", "Vélo", "T2", "Course"])
    #expect(segments.map(\.isTransition) == [false, true, false, true, false])
    let totalShare: Double = segments.map(\.fraction).reduce(0, +)
    let bikeShare: Double = 4_200.0 / 9_000
    #expect(abs(totalShare - 1) < 0.000_001)
    #expect(abs(segments[2].fraction - bikeShare) < 0.000_001)
}

@Test func untimedLegsAreLeftOut() {
    #expect(RaceLegsTimeline.segments([leg("swim", 0), leg("run", 0)]).isEmpty)
    #expect(RaceLegsTimeline.segments([leg("swim", 0), leg("run", 600)]).map(\.label) == ["Course"])
}

@Test func barWidthsFillTheWidthAndKeepTransitionsVisible() {
    let segments = RaceLegsTimeline.segments(triathlonLegs)
    let widths = RaceLegsTimeline.widths(segments, in: 300, minimum: 3, gap: 2)
    let drawn: Double = widths.reduce(0, +)
    #expect(abs(drawn - 292) < 0.000_001)
    #expect(widths[3] == 3)
    #expect(widths[2] > widths[4])
    #expect(widths[4] > widths[0])
}

// MARK: - Target and delta

@Test func targetTimesAreReadFromTheGoalsWords() {
    #expect(RaceTime.targetSeconds(from: "Sub 2h30") == 9_000)
    #expect(RaceTime.targetSeconds(from: "2:28:00") == 8_880)
    #expect(RaceTime.targetSeconds(from: "1h05'30") == 3_930)
    #expect(RaceTime.targetSeconds(from: "moins de 3h") == 10_800)
    #expect(RaceTime.targetSeconds(from: "45:30") == 2_730)
    #expect(RaceTime.targetSeconds(from: "50 min") == 3_000)
    #expect(RaceTime.targetSeconds(from: "Finir") == nil)
    #expect(RaceTime.targetSeconds(from: nil) == nil)
}

@Test func theFinalTimeReadsAgainstTheTarget() throws {
    let result = try #require(RaceResultModel.make(durationSec: 8_808, legs: triathlonLegs, targetPerformance: "Sub 2h30"))
    #expect(RaceTime.clock(result.durationSec) == "2:26:48")
    #expect(result.delta?.isAhead == true)
    #expect(result.delta?.label == "−3:12 vs objectif")
    #expect(RaceDelta(seconds: 65).label == "+1:05 vs objectif")
}

@Test func theLegsStandInForAMissingDuration() throws {
    let result = try #require(RaceResultModel.make(durationSec: nil, legs: triathlonLegs, targetPerformance: "Finir"))
    #expect(result.durationSec == 9_000)
    #expect(result.delta == nil)
    #expect(result.summaryLine == "2:30:00")
    #expect(RaceResultModel.make(durationSec: nil, legs: [], targetPerformance: nil) == nil)
}

// MARK: - Résumé race moment

@Test func raceDayMapsToTheDayCard() throws {
    let response = try todayJSON(race: """
    {"goalId":"g1","title":"Triathlon de Paris","raceFormat":"Triathlon M","targetPerformance":"Sub 2h30",
     "targetDate":"2026-10-12","phase":"raceDay","activity":null}
    """)
    let race = try #require(TodayFoldMapper.map(response).race)
    #expect(race.eyebrow == "Jour J")
    #expect(race.title == "Triathlon de Paris")
    #expect(race.formatLine == "Triathlon M")
    #expect(race.targetLine == "Objectif · Sub 2h30")
    #expect(race.result == nil)
    #expect(race.activityId == nil)
    #expect(race.coachLine == "Le travail est fait. Pars à ton allure, le reste suit.")
}

@Test func theDayAfterMapsToTheResult() throws {
    let response = try todayJSON(race: """
    {"goalId":"g1","title":"Triathlon de Paris","raceFormat":null,"targetPerformance":"Sub 2h30",
     "targetDate":"2026-10-11","phase":"postRace",
     "activity":{"id":"a1","title":"Triathlon de Paris","durationSec":8808,
       "legs":[{"kind":"swim","label":"Swim","durationSec":1800,"sourceActivityId":"s1"},
               {"kind":"transition","label":"T1","durationSec":120},
               {"kind":"bike","label":"Bike","durationSec":4200},
               {"kind":"transition","label":"T2","durationSec":60},
               {"kind":"run","label":"Run","durationSec":2628}]}}
    """)
    let race = try #require(TodayFoldMapper.map(response).race)
    #expect(race.eyebrow == "Hier · Course terminée")
    #expect(race.targetLine == nil)
    #expect(race.activityId == "a1")
    #expect(race.result?.segments.map(\.label) == ["Natation", "T1", "Vélo", "T2", "Course"])
    #expect(race.result?.summaryLine == "2:26:48 · −3:12 vs objectif")
    #expect(race.coachLine == "Reviens sur ta course : ce qui a marché, où tu peux progresser.")
    #expect(response.race?.activity?.legs.first?.sourceActivityId == "s1")
}

@Test func anUnknownPhaseDropsTheCardNotTheDay() throws {
    let response = try todayJSON(race: """
    {"goalId":"g1","title":"T","targetDate":"2026-10-12","phase":"taper"}
    """)
    #expect(TodayFoldMapper.map(response).race == nil)
    #expect(try todayJSON(race: nil).race == nil)
}

// MARK: - Activity ↔ goal

@Test func activityDetailDecodesItsGoalAndOlderPayloads() throws {
    let linked = Data("""
    {"id":"a1","type":"TRIATHLON","date":"2026-10-11T07:30:00.000Z","goalId":"g1",
     "goal":{"id":"g1","title":"Triathlon de Paris","raceFormat":"M","targetPerformance":"Sub 2h30","targetDate":"2026-10-11"},
     "multisportLegs":[{"kind":"swim","label":"Swim","durationSec":1800}]}
    """.utf8)
    let detail = try JSONDecoder().decode(V1ActivityDetail.self, from: linked)
    #expect(detail.goalId == "g1")
    #expect(detail.goal?.targetPerformance == "Sub 2h30")
    #expect(detail.multisportLegs.first?.sourceActivityId == nil)
    #expect(detail.withGoal(nil).goal == nil)

    let older = Data(#"{"id":"a2","type":"RUN","date":"2026-10-11T07:30:00Z"}"#.utf8)
    #expect(try JSONDecoder().decode(V1ActivityDetail.self, from: older).goal == nil)
}

@Test func goalDetailListsItsLinkedSessions() throws {
    let payload = Data("""
    {"id":"g1","title":"T","activities":[
      {"id":"a1","title":"Triathlon de Paris","type":"TRIATHLON","date":"2026-10-11T07:30:00.000Z","duration":8808},
      {"id":"bad"}]}
    """.utf8)
    let activities = try JSONDecoder().decode(V1GoalDetailPayload.self, from: payload).activities
    #expect(activities.map(\.id) == ["a1"])
    #expect(activities.first?.type == .triathlon)
    #expect(try JSONDecoder().decode(V1GoalDetailPayload.self, from: Data(#"{"id":"g1"}"#.utf8)).activities.isEmpty)
}

@Test func linkCandidatesAreRacesNearestTheSessionFirst() {
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let goals = [
        V1Goal(id: "far", title: "Far", kind: .race, targetDate: day.addingTimeInterval(90 * 86_400)),
        V1Goal(id: "metric", title: "Poids", kind: .metric),
        V1Goal(id: "undated", title: "Undated", kind: .race),
        V1Goal(id: "near", title: "Near", kind: .race, targetDate: day.addingTimeInterval(-86_400)),
    ]
    #expect(ActivityGoalCandidates.ordered(goals, around: day).map(\.id) == ["near", "far", "undated"])
}
