import Foundation
import Testing
@testable import Sharpit

struct IncomingLinkTests {
    private func link(_ raw: String) -> IncomingLink? {
        IncomingLink.parse(URL(string: raw)!)
    }

    @Test func garminCallbackOnTheApexCarriesItsStatus() {
        #expect(link("https://sharpit.app/connect/garmin/callback?garmin=connected") == .garminCallback(status: "connected"))
        #expect(link("https://sharpit.app/connect/garmin/callback") == .garminCallback(status: nil))
    }

    @Test(arguments: [
        "https://api.sharpit.app/connect/garmin/callback?garmin=connected",
        "https://web.sharpit.app/connect/garmin/callback?garmin=connected",
        "https://sharpit.app.evil.example/connect/garmin/callback?garmin=connected",
        "http://sharpit.app/connect/garmin/callback?garmin=connected",
        "app.sharpit.ios://connect/garmin/callback?garmin=connected",
    ])
    func linksOffTheApexAreIgnored(raw: String) {
        #expect(link(raw) == nil)
    }

    /// A widget's session opens itself: the activity once done, its prescription before.
    @Test func aSessionLinkOpensTheSessionItself() {
        #expect(link("https://sharpit.app/activity/act_42") == .activity(id: "act_42"))
        #expect(link("https://sharpit.app/plan/session/ps_7") == .plannedSession(id: "ps_7"))
        #expect(link("https://sharpit.app/activity/") == .tab(.activity) || link("https://sharpit.app/activity/") == nil)
        #expect(link("https://sharpit.app/plan/session/a/b") != .plannedSession(id: "a/b"))
    }

    @Test func aDoneSessionInTheWidgetLinksToItsActivity() {
        let done = WidgetSnapshot.Session(id: "act_42", isDone: true, title: "Seuil", sport: .run, figures: [])
        let planned = WidgetSnapshot.Session(id: "line", isDone: false, title: "Seuil", sport: .run, plannedSessionId: "ps_7", figures: [])
        #expect(link(done.link.absoluteString) == .activity(id: "act_42"))
        #expect(link(planned.link.absoluteString) == .plannedSession(id: "ps_7"))
    }

    @Test func webPathsOpenTheirTab() {
        #expect(link("https://sharpit.app/today") == .tab(.today))
        #expect(link("https://sharpit.app/activities") == .tab(.activity))
        #expect(link("https://sharpit.app/me") == .tab(.body))
        #expect(link("https://sharpit.app/settings") == .settings(nil))
        #expect(link("https://sharpit.app/settings/sources") == .settings(.sources))
        #expect(link("https://sharpit.app/goals") == .goals)
        #expect(link("https://sharpit.app/unknown") == nil)
    }

    @Test func theScanWidgetOpensTheScannerOnlyOnOurHost() {
        #expect(link("https://sharpit.app/nutrition/scan") == .foodScan)
        #expect(link("https://api.sharpit.app/nutrition/scan") == nil)
    }
}

@MainActor
@Test func openingTheScannerGoesToRésuméAndWaitsForIt() {
    let router = ShellRouter()
    router.select(.coach)

    router.openFoodScan()

    #expect(router.selectedTab == .today)
    #expect(router.pendingFoodScan)
}
