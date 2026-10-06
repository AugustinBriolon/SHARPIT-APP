import Testing
@testable import Sharpit

@Suite struct RouteReplayPathTests {
    private func point(_ value: Double) -> V1ActivityCoordinate {
        V1ActivityCoordinate(latitude: value, longitude: value)
    }

    @Test func theStartIsTheFirstPointAndTheEndTheWholePath() {
        let path = [point(0), point(1), point(2)]
        #expect(RouteReplayPath.prefix(path, progress: 0) == [point(0)])
        #expect(RouteReplayPath.prefix(path, progress: 1) == path)
    }

    @Test func theLineEndsBetweenTwoRecordedPoints() {
        let path = [point(0), point(1), point(2)]
        #expect(RouteReplayPath.prefix(path, progress: 0.25) == [point(0), point(0.5)])
        #expect(RouteReplayPath.prefix(path, progress: 0.5) == [point(0), point(1)])
    }

    @Test func stretchesAreCutAtTheSameShareOfTheRoute() {
        // Five route points: stretches share their joint, as RouteIntensity builds them.
        let segments = [
            RouteIntensity.Segment(level: 0, coordinates: [point(0), point(1), point(2)]),
            RouteIntensity.Segment(level: 4, coordinates: [point(2), point(3), point(4)]),
        ]
        #expect(RouteReplayPath.prefix(segments, progress: 0.5) == [segments[0]])
        #expect(RouteReplayPath.prefix(segments, progress: 0.625) == [
            segments[0],
            RouteIntensity.Segment(level: 4, coordinates: [point(2), point(2.5)]),
        ])
        #expect(RouteReplayPath.prefix(segments, progress: 1) == segments)
        #expect(RouteReplayPath.prefix(segments, progress: 0).isEmpty)
    }
}
