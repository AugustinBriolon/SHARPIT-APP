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
        #expect(link("https://sharpit.app/today") == .today(.overview))
        #expect(link("https://sharpit.app/activities") == .tab(.activity))
        #expect(link("https://sharpit.app/me") == .tab(.body))
        #expect(link("https://sharpit.app/settings") == .settings(nil))
        #expect(link("https://sharpit.app/settings/sources") == .settings(.sources))
        #expect(link("https://sharpit.app/goals") == .goals)
        #expect(link("https://sharpit.app/unknown") == nil)
    }

    @Test func theScanWidgetOpensTheScannerOnlyOnOurHost() {
        #expect(link("https://sharpit.app/nutrition/scan") == .today(.foodScan))
        #expect(link("https://api.sharpit.app/nutrition/scan") == nil)
    }

    /// Sommeil and Nutrition are pages of Résumé: their widgets open them, not Résumé's top.
    @Test func theSleepAndNutritionWidgetsOpenTheirPage() {
        #expect(link("https://sharpit.app/sleep") == .today(.sleep))
        #expect(link("https://sharpit.app/nutrition") == .today(.nutrition))
    }

    @Test func aLockedOrHiddenWidgetOpensTheSettingThatUndoesIt() {
        #expect(link("https://sharpit.app/settings/pro") == .settings(.pro))
        #expect(link("https://sharpit.app/settings/features") == .settings(.features))
    }
}

/// Every widget's tap, as the widget builds it, lands on the page it stands for.
struct WidgetLinkTests {
    private func destination(
        _ path: String,
        unlocked: Bool = true,
        feature: SharpitFeature? = nil,
        features: V1FeaturePrefs = V1FeaturePrefs()
    ) -> IncomingLink? {
        IncomingLink.parse(WidgetSnapshot.link(path, unlocked: unlocked, feature: feature, features: features))
    }

    @Test func eachWidgetOpensItsPage() {
        #expect(destination("/today") == .today(.overview))
        #expect(destination("/sleep") == .today(.sleep))
        #expect(destination("/nutrition", feature: .nutrition) == .today(.nutrition))
        #expect(destination("/nutrition/scan", feature: .nutrition) == .today(.foodScan))
        #expect(destination("/corps", feature: .health) == .tab(.body))
        #expect(destination("/plan", feature: .regularity) == .tab(.plan))
        #expect(destination("/activity") == .tab(.activity))
        #expect(destination("/coach") == .tab(.coach))
        #expect(destination("/goals") == .goals)
    }

    @Test func aLockedWidgetOpensSharpItPro() {
        #expect(destination("/sleep", unlocked: false) == .settings(.pro))
        #expect(destination("/corps", unlocked: false, feature: .health) == .settings(.pro))
    }

    @Test func aHiddenWidgetOpensPagesEtWidgets() {
        let features = V1FeaturePrefs(nutrition: false)
        #expect(destination("/nutrition", feature: .nutrition, features: features) == .settings(.features))
        #expect(destination("/nutrition/scan", feature: .nutrition, features: features) == .settings(.features))
    }
}

@MainActor
@Test func openingTheScannerGoesToRésuméAndWaitsForIt() {
    let router = ShellRouter()
    router.select(.coach)

    router.openToday(.foodScan)

    #expect(router.selectedTab == .today)
    #expect(router.pendingTodayPage == .foodScan)
}

@MainActor
@Test func aWidgetTappedUnderParamètresClosesIt() {
    let router = ShellRouter()
    router.openSettings()

    router.openToday(.sleep)

    #expect(!router.isShowingSettings)
    #expect(router.pendingTodayPage == .sleep)
}

/// A link heard before the tabs exist — a cold launch from a widget — waits to be taken once.
@MainActor
@Test func theInboxKeepsALinkUntilItIsTaken() {
    let inbox = IncomingLinkInbox()
    inbox.receive(URL(string: "https://evil.example/today")!)
    #expect(inbox.pending == nil)

    let url = URL(string: "https://sharpit.app/sleep")!
    inbox.receive(url)
    #expect(inbox.take() == url)
    #expect(inbox.take() == nil)
}
