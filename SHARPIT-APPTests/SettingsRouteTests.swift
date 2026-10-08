import Testing
@testable import Sharpit

/// Calendar sync lives under Sources › Priorités; Paramètres no longer has a dedicated route.
@Test func settingsRoutesOmitDedicatedCalendarEntry() {
    let routes: [SettingsRoute] = [
        .account, .pro, .sources, .equipment, .thresholds, .privacy,
        .notifications, .density, .features, .ownFoods, .feedback,
    ]
    #expect(routes.count == 11)
    #expect(routes.contains(.sources))
}
