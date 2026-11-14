import Testing
@testable import Sharpit

private func sample(hr: Double? = nil, speed: Double? = nil) -> V1ActivityStreamSample {
    V1ActivityStreamSample(t: 0, d: 0, alt: nil, hr: hr, watts: nil, cadence: nil, speed: speed)
}

private func route(_ count: Int) -> [V1ActivityCoordinate] {
    (0..<count).map { V1ActivityCoordinate(latitude: 45 + Double($0) * 0.001, longitude: 4.8) }
}

@Test func heartRateColoursTheRouteFromEasyToHard() throws {
    let samples = (0..<100).map { sample(hr: 120 + Double($0)) }
    let intensity = try #require(RouteIntensity.make(route: route(100), samples: samples))

    #expect(intensity.metric == .heartRate)
    #expect(intensity.segments.first?.level == 0)
    #expect(intensity.segments.last?.level == RouteIntensity.levels - 1)
    #expect(intensity.segments.map(\.level) == intensity.segments.map(\.level).sorted())
}

@Test func stretchesJoinWithoutAGap() throws {
    let samples = (0..<50).map { sample(hr: $0 < 25 ? 120 : 180) }
    let intensity = try #require(RouteIntensity.make(route: route(50), samples: samples))

    for (previous, next) in zip(intensity.segments, intensity.segments.dropFirst()) {
        #expect(previous.coordinates.last == next.coordinates.first)
    }
}

@Test func speedStandsInWithoutHeartRate() throws {
    let samples = (0..<40).map { sample(speed: 2 + Double($0) * 0.1) }
    #expect(try #require(RouteIntensity.make(route: route(40), samples: samples)).metric == .speed)
}

@Test func aFlatOrMissingSignalDrawsNoHeatmap() {
    #expect(RouteIntensity.make(route: route(30), samples: (0..<30).map { _ in sample(hr: 140) }) == nil)
    #expect(RouteIntensity.make(route: route(30), samples: (0..<30).map { _ in sample() }) == nil)
    #expect(RouteIntensity.make(route: [], samples: [sample(hr: 140)]) == nil)
}

@Test func aRecordingOffersTheSignalsItCarriesThenPlain() {
    let both = (0..<40).map { sample(hr: 120 + Double($0), speed: 3 + Double($0) * 0.05) }
    #expect(RouteIntensity.metrics(in: both) == [.heartRate, .speed])
    #expect(RouteColouring.options(for: [.heartRate, .speed]) == [.heartRate, .speed, .plain])
    #expect(RouteColouring.options(for: []).isEmpty)
    #expect(RouteIntensity.make(route: route(40), samples: both, metric: .speed)?.metric == .speed)
    // A signal asked for that the recording lacks colours nothing, rather than another signal.
    let heartOnly = (0..<40).map { sample(hr: 120 + Double($0)) }
    #expect(RouteIntensity.make(route: route(40), samples: heartOnly, metric: .speed) == nil)
}

@MainActor @Test func theColoursSpanIsSaidInTheSignalsUnit() throws {
    let heart = try #require(RouteIntensity.make(route: route(101), samples: (0...100).map { sample(hr: 100 + Double($0)) }))
    #expect(heart.rangeText(asPace: true) == "110 – 190 bpm")
    let speed = try #require(RouteIntensity.make(route: route(101), samples: (0...100).map { sample(speed: 4 + Double($0) * 0.01) }))
    #expect(speed.rangeText(asPace: false) == "14,8 – 17,6 km/h")
    #expect(speed.rangeText(asPace: true) == "4'04\" – 3'24\" /km")
}
