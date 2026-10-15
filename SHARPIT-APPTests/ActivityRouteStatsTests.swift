import Foundation
import Testing
@testable import Sharpit

struct ActivityRouteStatsTests {
    @Test func runMatchesMapCardFormats() {
        let stats = ActivityRouteStats(V1ActivityListItem(
            type: .run,
            date: .now,
            duration: 1_690,
            distanceM: 5_200
        ))
        #expect(stats.distance == .init(value: "5,20", unit: "km"))
        #expect(stats.duration == .init(value: "28:10", unit: "min"))
        #expect(stats.paceLabel == "Allure")
        #expect(stats.pace == .init(value: "5:25", unit: "/km"))
    }

    @Test func bikeShowsSpeed() {
        let stats = ActivityRouteStats(V1ActivityListItem(
            type: .bike,
            date: .now,
            duration: 3_600,
            distanceM: 30_000
        ))
        #expect(stats.paceLabel == "Vitesse")
        #expect(stats.pace.unit == "km/h")
    }
}
