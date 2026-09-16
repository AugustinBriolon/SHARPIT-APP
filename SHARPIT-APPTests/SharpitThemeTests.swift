import SwiftUI
import Testing
@testable import Sharpit

@Test func postureProtectMapsToOrange() {
    #expect(SharpitPostureStyle.color(for: .protect) == Color.orange)
}

@Test func postureSteadyUsesAccent() {
    #expect(SharpitPostureStyle.color(for: .steady) == Color.accentColor)
}

@Test func canvasTopNilUsesAccentWash() {
    let top = SharpitPostureStyle.canvasTop(for: nil)
    #expect(top != Color.clear)
}

@Test func spacingPageInsetIs20() {
    #expect(SharpitSpacing.pageInset == 20)
}

@Test func eyebrowUsesUppercaseTrackingContract() {
    #expect(SharpitTypography.eyebrowTracking == 1.6)
}
