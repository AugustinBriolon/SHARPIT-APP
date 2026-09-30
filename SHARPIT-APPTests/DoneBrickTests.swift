import Foundation
import Testing
@testable import Sharpit

private func card(legs: [V1TodayBrickLeg], transitions: [Int?]? = [124]) -> SessionCardModel {
    SessionCardModel(
        id: "act-bike",
        kind: .done,
        title: "Brick · Vélo → Course",
        subtitle: "1h50 · 136 TSS · Transition 2 min 04",
        metrics: [],
        sport: nil,
        priority: false,
        plannedSessionId: "leg-bike",
        brickLegs: legs,
        brickTransitionsSec: transitions
    )
}

private let bike = V1TodayBrickLeg(
    id: "leg-bike", type: "BIKE", title: "Vélo", durationMin: 85,
    completed: true, activityId: "act-bike",
    actual: V1TodayBrickLegActual(durationSec: 4_815, load: 95, rpe: 6, feeling: "Bonnes jambes")
)
private let run = V1TodayBrickLeg(id: "leg-run", type: "RUN", title: "Course", durationMin: 30)

@Test func aDoneBrickLineOpensAsTheChainItWas() throws {
    let brick = try #require(DoneBrickPreview(card: card(legs: [bike, run])))

    #expect(brick.chain == "Vélo → Course")
    #expect(brick.legs.map(\.isDone) == [true, false])
    #expect(brick.legs.first?.activityId == "act-bike")
    #expect(brick.transition(before: 1) == 124)
    #expect(brick.transition(before: 0) == nil)
}

@Test func aPlannedOrSingleLineIsNoDoneBrick() {
    var planned = card(legs: [bike, run])
    planned.kind = .planned
    #expect(DoneBrickPreview(card: planned) == nil)
    #expect(DoneBrickPreview(card: card(legs: [bike])) == nil)
}

@Test func aDoneLegReadsItsDurationAndRPE() throws {
    let brick = try #require(DoneBrickPreview(card: card(legs: [bike, run])))
    #expect(DoneBrickFormat.legMeta(brick.legs[0]) == "1h20 · RPE 6")
    #expect(DoneBrickFormat.legMeta(brick.legs[1]) == "À faire")
}

@Test func aTransitionReadsAsTheWebWritesIt() {
    #expect(DoneBrickFormat.transition(124) == "2 min 04")
    #expect(DoneBrickFormat.transition(45) == "45 s")
}

@Test func aBrickLegDecodesWithAndWithoutWhatItWas() throws {
    let done = try JSONDecoder().decode(V1TodayBrickLeg.self, from: Data("""
    {"id":"leg-bike","type":"BIKE","title":"Vélo","durationMin":85,"completed":true,"activityId":"act-bike",
     "actual":{"durationSec":4815,"load":95.2,"rpe":6,"feeling":"Bonnes jambes"}}
    """.utf8))
    #expect(done.actual?.rpe == 6)
    #expect(done.activityId == "act-bike")

    let older = try JSONDecoder().decode(V1TodayBrickLeg.self, from: Data("""
    {"id":"leg-run","type":"RUN","title":"Course","durationMin":30}
    """.utf8))
    #expect(older.completed == nil)
    #expect(older.actual == nil)
}
