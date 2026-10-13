import Foundation
import Testing
@testable import Sharpit

@MainActor
@Suite struct RaceProjectionTests {
    private func decodeGoal(_ projection: String?) throws -> V1Goal {
        let field = projection.map { #", "projection": \#($0)"# } ?? ""
        let json = #"{"id": "g1", "title": "70.3 Versailles", "kind": "RACE", "achieved": false\#(field)}"#
        return try JSONDecoder().decode(V1Goal.self, from: Data(json.utf8))
    }

    private let fullProjection = """
    {
      "finishSec": 20460, "lowSec": 20100, "highSec": 20880,
      "targetSec": 21600, "deltaSec": -1140,
      "legs": [
        {"kind": "swim", "sec": 2280, "source": "profile"},
        {"kind": "t1", "sec": 180, "source": "default"},
        {"kind": "bike", "sec": 10500, "source": "recent"},
        {"kind": "t2", "sec": 120, "source": "default"},
        {"kind": "run", "sec": 7380, "source": "history"}
      ],
      "confidence": "medium",
      "missing": ["Renseigne ta CSS en natation"],
      "frozenAt": "2026-10-10T06:00:00.000Z",
      "todaySec": 21120, "regularity": 0.82, "trend": {"secPerWeek": -165},
      "history": [
        {"weekKey": "2026-W33", "date": "2026-08-17T00:00:00.000Z", "finishSec": 21780},
        {"weekKey": "2026-W37", "date": "2026-09-14T00:00:00.000Z", "finishSec": 21000}
      ]
    }
    """

    @Test func decodesAFullProjection() throws {
        let projection = try #require(try decodeGoal(fullProjection).projection)
        #expect(projection.finishSec == 20460)
        #expect(projection.deltaSec == -1140)
        #expect(projection.legs.map(\.kind) == [.swim, .t1, .bike, .t2, .run])
        #expect(projection.legs.map(\.source) == [.profile, .default, .recent, .default, .history])
        #expect(projection.confidence == .medium)
        #expect(projection.missing == ["Renseigne ta CSS en natation"])
        #expect(projection.frozenAt != nil)
        #expect(projection.todaySec == 21120)
        #expect(projection.regularity == 0.82)
        #expect(projection.trend?.secPerWeek == -165)
        #expect(projection.history.map(\.weekKey) == ["2026-W33", "2026-W37"])
    }

    @Test func malformedExtrasDropQuietly() throws {
        let projection = try #require(try decodeGoal("""
        {"finishSec": 3000, "lowSec": 2900, "highSec": 3100, "todaySec": "x", "regularity": null,
         "trend": {"secPerWeek": "fast"}, "history": [{"weekKey": "W1", "date": "nope", "finishSec": 1},
         {"weekKey": "W2", "date": "2026-09-14T00:00:00.000Z", "finishSec": 3100}]}
        """).projection)
        #expect(projection.todaySec == nil)
        #expect(projection.regularity == nil)
        #expect(projection.trend == nil)
        #expect(projection.history.map(\.weekKey) == ["W2"])
    }

    @Test func trajectoryEndsOnTheCurrentProjection() throws {
        let now = try Date.fromAPI("2026-10-12T00:00:00.000Z")
        let readout = RaceProjectionReadout(try #require(try decodeGoal(fullProjection).projection), now: now)
        #expect(readout.trajectory.map(\.finishSec) == [21780, 21000, 20460])
        #expect(readout.trajectoryLine == "−22 min en 8 semaines")
        #expect(readout.todayLine == "Si c'était aujourd'hui : 5h52")
        #expect(readout.confidenceLine == "Régularité : 82 % des séances faites · fiabilité moyenne")
    }

    @Test func aLoneProjectionDrawsNoTrajectory() {
        let readout = RaceProjectionReadout(V1RaceProjection(finishSec: 3000, lowSec: 2900, highSec: 3100))
        #expect(readout.trajectory.isEmpty)
        #expect(readout.trajectoryLine == nil)
        #expect(readout.todayLine == nil)
        #expect(readout.confidenceLine == nil)
    }

    @Test func trajectoryReadsSlowerAndStable() {
        let start = Date(timeIntervalSince1970: 0)
        let week = 604_800.0
        let slower = RaceProjectionReadout(
            V1RaceProjection(finishSec: 3300, lowSec: 3200, highSec: 3400, history: [.init(weekKey: "a", date: start, finishSec: 3000)]),
            now: start.addingTimeInterval(week)
        )
        #expect(slower.trajectoryLine == "+5 min en 1 semaine")
        let stable = RaceProjectionReadout(
            V1RaceProjection(finishSec: 3010, lowSec: 2900, highSec: 3100, history: [.init(weekKey: "a", date: start, finishSec: 3000)]),
            now: start.addingTimeInterval(3 * week)
        )
        #expect(stable.trajectoryLine == "stable en 3 semaines")
    }

    @Test func noProjectionOrNullReadsNil() throws {
        #expect(try decodeGoal(nil).projection == nil)
        #expect(try decodeGoal("null").projection == nil)
    }

    @Test func malformedProjectionNeverBreaksTheGoal() throws {
        let goal = try decodeGoal(#"{"finishSec": "soon", "legs": 3}"#)
        #expect(goal.id == "g1")
        #expect(goal.projection == nil)
    }

    @Test func unknownValuesAreTolerated() throws {
        let projection = try #require(try decodeGoal("""
        {"finishSec": 3000, "lowSec": 2900, "highSec": 3100, "targetSec": null, "deltaSec": null,
         "legs": [{"kind": "kayak", "sec": 600}, {"kind": "run", "sec": 3000, "source": "oracle"}],
         "confidence": "certain", "missing": [], "frozenAt": null}
        """).projection)
        #expect(projection.legs == [.init(kind: .run, sec: 3000, source: nil)])
        #expect(projection.confidence == nil)
        #expect(projection.frozenAt == nil)
    }

    @Test func roundTripsThroughEncoding() throws {
        let goal = try decodeGoal(fullProjection)
        let again = try JSONDecoder().decode(V1Goal.self, from: JSONEncoder().encode(goal))
        #expect(again.projection == goal.projection)
    }

    @Test func readoutSaysRangeGapConfidenceAndSources() throws {
        let readout = RaceProjectionReadout(try #require(try decodeGoal(fullProjection).projection))
        #expect(readout.finishLabel == "5h41")
        #expect(readout.rangeLabel == "5h35 – 5h48")
        #expect(readout.delta?.label == "−19:00 vs objectif")
        #expect(readout.confidenceLabel == "fiabilité moyenne")
        #expect(readout.legs.map(\.segment.label) == ["Natation", "T1", "Vélo", "T2", "Course"])
        #expect(readout.legs.map(\.sourceLabel) == [
            "valeur du profil", "valeur par défaut", "d'après tes courses récentes", "valeur par défaut", "d'après ton historique",
        ])
        #expect(readout.legs[2].timeLabel == "2:55:00")
        #expect(abs(readout.legs.reduce(0) { $0 + $1.segment.fraction } - 1) < 0.0001)
    }

    @Test func readoutWithoutTargetOrConfidenceStaysQuiet() {
        let readout = RaceProjectionReadout(V1RaceProjection(finishSec: 2700, lowSec: 2640, highSec: 2790))
        #expect(readout.delta == nil)
        #expect(readout.confidenceLabel == nil)
        #expect(readout.legs.isEmpty)
        #expect(readout.rangeLabel == "44min – 46min")
    }

    @Test func plannedSaysWhenItWasRecalculated() {
        let frozen = RaceProjectionReadout(V1RaceProjection(finishSec: 21_912, lowSec: 21_000, highSec: 22_500, frozenAt: Date()))
        let live = RaceProjectionReadout(V1RaceProjection(finishSec: 21_912, lowSec: 21_000, highSec: 22_500))
        #expect(frozen.plannedVsActual(actualSeconds: 20_403) == "Prévu 6:05 · Réalisé 5:40")
        #expect(live.plannedVsActual(actualSeconds: 20_403) == "Prévu (recalculé) 6:05 · Réalisé 5:40")
    }

    @Test func storeReadsTheServerProjectionForRacesOnly() throws {
        let store = GoalStore(client: StubGoalClient(stubbedGoals: []), plannedSessionClient: nil, profileClient: nil, activityClient: nil, tokenProvider: { "t" })
        let race = try decodeGoal(fullProjection)
        #expect(store.raceProjection(for: race)?.finishLabel == "5h41")
        #expect(store.raceProjection(for: try decodeGoal(nil)) == nil)
        var metric = race
        metric.kind = .metric
        #expect(store.raceProjection(for: metric) == nil)
    }
}
