import Foundation
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

@Test func theProfileRowSaysAgeAndHeightWithWhatItHolds() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14))!
    let birth = calendar.date(from: DateComponents(year: 1992, month: 3, day: 2))!
    #expect(SettingsReadout.profile(birthDate: birth, heightCm: 181, now: now, calendar: calendar) == "34 ans · 181 cm")
    #expect(SettingsReadout.profile(birthDate: nil, heightCm: 181, now: now, calendar: calendar) == "181 cm")
    #expect(SettingsReadout.profile(birthDate: nil, heightCm: nil, now: now, calendar: calendar) == nil)
}
