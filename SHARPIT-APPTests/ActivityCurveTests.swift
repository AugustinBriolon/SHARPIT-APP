import Foundation
import Testing
@testable import Sharpit

private func sample(_ t: Double, hr: Double? = nil, speed: Double? = nil, alt: Double? = nil) -> V1ActivityStreamSample {
    V1ActivityStreamSample(t: t, d: 0, alt: alt, hr: hr, watts: nil, cadence: nil, speed: speed)
}

@Test func aLongSessionIsThinnedToALanesWidthKeepingItsAverage() throws {
    let samples = (0..<3_000).map { sample(Double($0), hr: $0.isMultiple(of: 2) ? 140 : 160) }
    let curve = try #require(ActivityCurve(metric: .heartRate, samples: samples))
    #expect(curve.points.count == ActivityCurve.maxPoints)
    #expect(curve.average == 150)
    #expect(curve.peak == 160)
    #expect(curve.summary == "moy. 150 · max 160")
}

@Test func paceAveragesTheSpeedAndIsDrawnFasterHigher() throws {
    // 4 m/s and 2 m/s: 250 s/km and 500 s/km, a mean speed of 3 m/s, 5:33/km.
    let samples = (0..<10).map { sample(Double($0) * 60, speed: $0.isMultiple(of: 2) ? 4 : 2) }
    let curve = try #require(ActivityCurve(metric: .pace, samples: samples))
    #expect(curve.reading(curve.average) == "5:33")
    #expect(curve.reading(curve.peak) == "4:10")
    #expect(curve.plotted(250) > curve.plotted(500))
    #expect(curve.axisLabel(plotted: curve.plotted(250)) == "4:10")
}

@Test func aMeasureWithOneSampleDrawsNoLane() {
    #expect(ActivityCurve(metric: .heartRate, samples: [sample(0, hr: 140), sample(1)]) == nil)
}

@Test func lanesOpenOnHeartRateEffortAndClimb() {
    #expect(ActivityCurve.defaultSelection(from: [.heartRate, .pace, .power, .elevation, .cadence]) == [.heartRate, .power, .elevation])
    #expect(ActivityCurve.defaultSelection(from: [.pace, .cadence]) == [.pace])
    #expect(ActivityCurve.defaultSelection(from: [.cadence]) == [.cadence])
}

@Test func theClockReadsHoursAndRefusesWhatIsNotATime() {
    #expect(ActivityCurve.clock(3_750) == "1:02:30")
    #expect(ActivityCurve.clock(312) == "5:12")
    #expect(ActivityCurve.clock(.nan) == "—")
}
