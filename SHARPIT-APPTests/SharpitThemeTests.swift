import SwiftUI
import Testing
@testable import Sharpit

@Test func postureProtectMapsToOrange() {
    #expect(SharpitPostureStyle.color(for: .protect) == Color.orange)
}

@Test func postureSteadyUsesAccent() {
    #expect(SharpitPostureStyle.color(for: .steady) == Color.accentColor)
}

@Test func canvasWashUsesMintWithoutPosture() {
    let top = SharpitCanvas.washTop(for: nil)
    #expect(top != Color.clear)
    #expect(SharpitCanvas.washMid != Color.clear)
}

@Test func spacingLadderDerivesFromGoldenRatio() {
    #expect(SharpitSpacing.base == 8)
    #expect(SharpitSpacing.xxs == 8)
    #expect(SharpitSpacing.xs == SharpitRatio.step(8, power: 1))
    #expect(SharpitSpacing.md == SharpitRatio.step(8, power: 2))
    #expect(SharpitSpacing.pageInset == SharpitSpacing.md)
    #expect(SharpitSpacing.lg == SharpitRatio.step(8, power: 3))
    #expect(SharpitSpacing.cardRadius == SharpitRatio.rounded(SharpitRatio.major(of: 40)))
}

@Test func ratioMajorMinorSplitWhole() {
    let whole: CGFloat = 100
    #expect(abs(SharpitRatio.major(of: whole) + SharpitRatio.minor(of: whole) - whole) < 0.01)
    #expect(SharpitRatio.major(of: whole) > SharpitRatio.minor(of: whole))
}

@Test func eyebrowUsesUppercaseTrackingContract() {
    #expect(SharpitTypography.eyebrowTracking == SharpitRatio.rounded(SharpitRatio.phi * 10) / 10)
}
