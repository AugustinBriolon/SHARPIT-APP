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

    @Test func webPathsOpenTheirTab() {
        #expect(link("https://sharpit.app/today") == .tab(.today))
        #expect(link("https://sharpit.app/activities") == .tab(.activity))
        #expect(link("https://sharpit.app/me") == .tab(.body))
        #expect(link("https://sharpit.app/settings") == .settings)
        #expect(link("https://sharpit.app/unknown") == nil)
    }
}
