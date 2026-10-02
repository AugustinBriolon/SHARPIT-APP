import Foundation
import Testing
@testable import Sharpit

@Test func theFingerReadsTheClosestMeasure() {
    let day: TimeInterval = 86_400
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let points = [0, 3, 7].map { CorpsPoint(date: start.addingTimeInterval(Double($0) * day), value: 70 + Double($0)) }

    #expect(CorpsFormat.nearest(points, to: start.addingTimeInterval(2 * day))?.value == 73)
    #expect(CorpsFormat.nearest(points, to: start.addingTimeInterval(-5 * day))?.value == 70)
    #expect(CorpsFormat.nearest([], to: start) == nil)
}
