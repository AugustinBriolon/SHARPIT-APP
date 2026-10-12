import CoreGraphics
import Foundation
import MapKit
import Testing
@testable import Sharpit

private func leg(
    _ kind: String, _ seconds: Double, label: String, distance: Double? = nil,
    moving: Double? = nil, hr: Double? = nil
) -> V1MultisportLeg {
    V1MultisportLeg(
        kind: kind, label: label, durationSec: seconds, movingDurationSec: moving, distanceM: distance,
        avgHr: hr, avgSpeedMs: nil, elevationM: nil, calories: nil, transitionIndex: nil
    )
}

private func sample(_ t: Double, _ d: Double, hr: Double? = 140) -> V1ActivityStreamSample {
    V1ActivityStreamSample(t: t, d: d, alt: nil, hr: hr, watts: nil, cadence: nil, speed: nil)
}

/// 100 s of race: swim 20, T1 10, bike 40, T2 10, run 20.
private let legs = [
    leg("swim", 20, label: "Swim", distance: 400),
    leg("transition", 10, label: "Transition", distance: 80, moving: 7, hr: 151.4),
    leg("bike", 40, label: "Bike", distance: 20_000),
    leg("transition", 10, label: "Transition"),
    leg("run", 20, label: "Run", distance: 5_000),
]

/// One path point and one sample per second, the latitude counting the seconds.
private func parent(seconds: Int = 100) -> V1ActivityStreamPayload {
    V1ActivityStreamPayload(
        available: true,
        path: (0...seconds).map { [Double($0), 2] },
        samples: (0...seconds).map { sample(Double($0), Double($0) * 10) },
        stats: nil
    )
}

private func coordinate(_ lat: Double, _ lon: Double = 2) -> V1ActivityCoordinate {
    V1ActivityCoordinate(latitude: lat, longitude: lon)
}

@MainActor
struct TriathlonCourseTests {

    // MARK: Slicing the parent

    @Test func eachLegTakesItsTimeWindowOfTheParentRecording() {
        let tracks = TriathlonCourse.tracks(legs: legs, parent: parent(), legStreams: [])
        #expect(tracks.map(\.segment.label) == ["Natation", "T1", "Vélo", "T2", "Course"])
        #expect(tracks[0].route.first?.latitude == 0)
        #expect(tracks[0].route.last?.latitude == 20)
        // Consecutive legs share their boundary point, so the course is drawn without a gap.
        #expect(tracks[1].route.first?.latitude == 20)
        #expect(tracks[2].route.first?.latitude == 30)
        #expect(tracks[2].route.last?.latitude == 70)
        #expect(tracks[4].route.last?.latitude == 100)
    }

    @Test func aLegsSamplesStartAtItsOwnStart() {
        let bike = TriathlonCourse.tracks(legs: legs, parent: parent(), legStreams: [])[2]
        #expect(bike.samples.first?.t == 0)
        #expect(bike.samples.first?.d == 0)
        #expect(bike.samples.last?.t == 40)
        #expect(bike.samples.last?.d == 400)
    }

    @Test func aParentThatDoesNotCoverTheRaceIsNotSliced() {
        let tracks = TriathlonCourse.tracks(legs: legs, parent: parent(seconds: 50), legStreams: [])
        #expect(tracks.allSatisfy { $0.route.isEmpty && $0.samples.isEmpty })
    }

    // MARK: Each leg's own recording

    @Test func aLegsOwnRecordingReplacesItsSliceAndATransitionBridgesTheGap() {
        let ownBike = V1ActivityStreamPayload(
            available: true,
            path: [[50, 5], [51, 5], [52, 5]],
            samples: [sample(0, 0), sample(3_600, 90_000)],
            stats: nil
        )
        let ownSwim = V1ActivityStreamPayload(available: true, path: [[10, 1], [11, 1]], samples: [], stats: nil)
        let tracks = TriathlonCourse.tracks(
            legs: legs,
            parent: nil,
            legStreams: [
                V1MultisportLegStream(leg: legs[0], stream: ownSwim),
                V1MultisportLegStream(leg: legs[2], stream: ownBike),
            ]
        )
        #expect(tracks[2].route.map(\.latitude) == [50, 51, 52])
        #expect(tracks[2].samples.last?.d == 90_000)
        // T1 has no GPS of its own: drawn from the swim's last point to the bike's first.
        #expect(tracks[1].route == [coordinate(11, 1), coordinate(50, 5)])
        // T2 has no leg after it with GPS: nothing to draw.
        #expect(tracks[3].route.isEmpty)
        #expect(tracks[4].route.isEmpty)
    }

    // MARK: Selection

    @Test func theSelectorReadsTheWholeCourseThenEachLeg() {
        let tracks = TriathlonCourse.tracks(legs: legs, parent: parent(), legStreams: [])
        let options = TriathlonCourse.options(tracks)
        #expect(options.map { $0.label } == ["Tout", "Natation", "T1", "Vélo", "T2", "Course"])
        #expect(options.map { $0.value } == [.overview, .leg(0), .leg(1), .leg(2), .leg(3), .leg(4)])
        #expect(TriathlonCourse.track(for: .leg(2), in: tracks)?.leg.kind == "bike")
        #expect(TriathlonCourse.track(for: .overview, in: tracks) == nil)
    }

    @Test func theCameraFramesTheLegOrTheCourseAndStaysForALegWithoutGPS() {
        let tracks = TriathlonCourse.tracks(legs: legs, parent: parent(), legStreams: [])
        #expect(TriathlonCourse.route(for: .leg(4), in: tracks).first?.latitude == 80)
        #expect(TriathlonCourse.route(for: .overview, in: tracks).count == tracks.map(\.route.count).reduce(0, +))
        let noGPS = TriathlonCourse.tracks(legs: legs, parent: nil, legStreams: [])
        #expect(TriathlonCourse.route(for: .leg(0), in: noGPS).isEmpty)
    }

    // MARK: Framing

    @Test func aRouteIsFramedInTheBandAboveThePanel() throws {
        let route = [coordinate(48.80, 2.10), coordinate(48.82, 2.12)]
        let region = try #require(RouteFraming.region(
            for: route, viewport: CGSize(width: 400, height: 800), visibleHeightShare: 0.5, margin: 1
        ))
        // Half the screen shows the route: the span doubles and the centre moves a quarter south.
        #expect(abs(region.span.latitudeDelta - 0.04) < 0.000_1)
        #expect(abs(region.center.latitude - (48.81 - 0.01)) < 0.000_1)
        #expect(abs(region.center.longitude - 2.11) < 0.000_1)
        #expect(RouteFraming.region(for: [], viewport: CGSize(width: 400, height: 800)) == nil)
    }

    @Test func aTinyTransitionStillOpensOnAReadableSpan() throws {
        let region = try #require(RouteFraming.region(
            for: [coordinate(48.8), coordinate(48.8001)], viewport: CGSize(width: 400, height: 400),
            margin: 1, minimumSpan: 0.002
        ))
        #expect(region.span.latitudeDelta >= 0.002)
    }

    // MARK: Leg readouts

    @Test func aLegReadsAsASessionOfItsSport() throws {
        let race = try JSONDecoder().decode(V1ActivityDetail.self, from: Data(#"""
        {"id":"a1","type":"TRIATHLON","date":"2026-10-11T07:30:00.000Z","load":312}
        """#.utf8))
        let run = race.leg(legs[4])
        #expect(run.type == .run)
        #expect(run.paceSecPerKm == 4)
        #expect(run.load == nil)
        let swim = race.leg(legs[0])
        #expect(swim.avgPaceSecPer100m == 5)
        #expect(swim.paceSecPerKm == nil)
        #expect(race.leg(legs[2]).paceSecPerKm == nil)
    }

    @Test func aTransitionSaysWhatItsRecordingCarries() {
        let rows = TriathlonTransitionReadout.rows(legs[1])
        #expect(rows.map(\.label) == ["Distance", "En mouvement", "À l’arrêt", "FC moyenne"])
        #expect(rows.map(\.value) == ["80 m", "0:07", "0:03", "151 bpm"])
        #expect(TriathlonTransitionReadout.rows(legs[3]).isEmpty)
    }
}
