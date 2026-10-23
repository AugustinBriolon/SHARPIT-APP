import Foundation
import Testing
@testable import Sharpit

@MainActor
struct ShellRouterPlanFocusTests {
    @Test func openPlanSelectsPlanAndKeepsTheDay() {
        let router = ShellRouter()
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        router.openPlan(on: day)

        #expect(router.selectedTab == .plan)
        #expect(router.planFocusDay == day)
    }

    @Test func tappingPlanAgainBumpsTheReselectTick() {
        let router = ShellRouter()
        router.tabBarSelected(.plan)
        #expect(router.planReselectTick == 0)

        router.tabBarSelected(.plan)
        #expect(router.planReselectTick == 1)

        router.tabBarSelected(.coach)
        router.tabBarSelected(.coach)
        #expect(router.planReselectTick == 1)
    }

    @Test func foldDayIdRoundTripsToItsLocalMidnight() {
        let date = TrainingDayId.date("2026-10-20")

        #expect(date.map { TrainingDayId.today(now: $0) } == "2026-10-20")
    }
}
