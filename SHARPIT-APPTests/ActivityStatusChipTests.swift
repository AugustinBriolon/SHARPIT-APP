import Foundation
import Testing
@testable import Sharpit

struct ActivityStatusChipTests {
    @Test func theNormalStateSaysNothing() {
        #expect(ActivityStatusId.active.chipTitle(untilDay: nil) == nil)
        #expect(ActivityStatusId.active.chipTitle(untilDay: "2026-11-03") == nil)
    }

    @Test func aModeWithoutAnEndIsJustNamed() {
        #expect(ActivityStatusId.injured.chipTitle(untilDay: nil) == "Blessé")
    }

    @Test func aModeWithAnEndNamesTheDay() {
        let title = ActivityStatusId.sick.chipTitle(untilDay: "2026-11-03")

        #expect(title?.hasPrefix("Malade · ") == true)
        #expect(title?.contains("3") == true)
    }

    @Test func anUnreadableDayFallsBackToTheName() {
        #expect(ActivityStatusId.paused.chipTitle(untilDay: "soon") == "En pause")
    }
}
