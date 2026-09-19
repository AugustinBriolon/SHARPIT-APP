import SwiftUI
import Testing
import UIKit
@testable import Sharpit

/// Resolves a token to concrete channels in one interface style.
///
/// Every token is a dynamic `UIColor`, so two tokens holding the same value are still
/// different objects — `==` on `Color` cannot answer "is this the brand green". Resolving
/// against a trait collection can.
private func channels(
    _ color: Color,
    style: UIUserInterfaceStyle = .light
) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
}

private func hex(_ color: Color, style: UIUserInterfaceStyle = .light) -> String {
    let (red, green, blue, _) = channels(color, style: style)
    return String(
        format: "#%02x%02x%02x",
        Int((red * 255).rounded()),
        Int((green * 255).rounded()),
        Int((blue * 255).rounded())
    )
}

// MARK: - Generated tokens

@Test func canvasIsSnowWhiteOnLightAndForestNightOnDark() {
    #expect(hex(SharpitColor.background) == "#fcfcf7")
    #expect(hex(SharpitColor.background, style: .dark) == "#0f1f0a")
}

@Test func inkIsForestDepths() {
    #expect(hex(SharpitColor.foreground) == "#1c3a13")
}

@Test func highlightIsLimePulseInBothThemes() {
    #expect(hex(SharpitColor.highlight) == "#d3fa99")
    #expect(hex(SharpitColor.highlight, style: .dark) == "#d3fa99")
}

@Test func inkBandInvertsBetweenThemes() {
    // Forest band on a light canvas, Lime band on a dark one.
    #expect(hex(SharpitColor.inkSurface) == "#1c3a13")
    #expect(hex(SharpitColor.inkSurface, style: .dark) == "#d3fa99")
}

@Test func hairlineBordersCarryTheirAlpha() {
    #expect(channels(SharpitColor.analysisBorder).alpha < 1)
}

@Test func sportIdentityMatchesTheWebFamilies() {
    #expect(hex(SharpitSportColor.color(SharpitSportColor.run)) == "#ea580c")
    #expect(hex(SharpitSportColor.color(SharpitSportColor.bike)) == "#059669")
    #expect(hex(SharpitSportColor.color(SharpitSportColor.other)) == "#2f6b28")
}

// MARK: - Posture

@Test func postureMapsOntoSemanticSignalTokens() {
    #expect(hex(SharpitPostureStyle.color(for: .steady)) == hex(SharpitColor.primary))
    #expect(hex(SharpitPostureStyle.color(for: .push)) == hex(SharpitColor.signalRecovery))
    #expect(hex(SharpitPostureStyle.color(for: .uncertain)) == hex(SharpitColor.signalNeutral))
}

@Test func protectIsProtectiveAmberNeverPunitiveRed() {
    #expect(hex(SharpitPostureStyle.color(for: .protect)) == hex(SharpitColor.signalCaution))
    #expect(hex(SharpitPostureStyle.color(for: .protect)) != hex(SharpitColor.signalRisk))
}

// MARK: - Spacing

@Test func spacingLadderSitsOnTheAppleGrid() {
    for step in [
        SharpitSpacing.xxs, SharpitSpacing.xs, SharpitSpacing.sm,
        SharpitSpacing.md, SharpitSpacing.lg, SharpitSpacing.xl,
    ] {
        #expect(step.truncatingRemainder(dividingBy: 4) == 0)
    }
}

@Test func spacingLadderAscends() {
    let ladder = [
        SharpitSpacing.xxs, SharpitSpacing.xs, SharpitSpacing.sm,
        SharpitSpacing.md, SharpitSpacing.lg, SharpitSpacing.xl,
    ]
    #expect(ladder == ladder.sorted())
    #expect(Set(ladder).count == ladder.count)
}

@Test func pageInsetMatchesTheSystemLayoutMargin() {
    #expect(SharpitSpacing.pageInset == 16)
}

@Test func cardRadiusComesFromTheExportedBrandRadius() {
    #expect(SharpitSpacing.cardRadius == SharpitTokens.radius)
    #expect(SharpitTokens.radius == 16)
}

@Test func analysisRadiiMirrorTheWebScale() {
    #expect(SharpitRadius.panel == SharpitTokens.radius * 0.875)
    #expect(SharpitRadius.panelLarge == SharpitTokens.radius * 1.125)
    #expect(SharpitRadius.small < SharpitRadius.panel)
}

// MARK: - Ratio

@Test func ratioMajorMinorSplitWhole() {
    let whole: CGFloat = 100
    #expect(abs(SharpitRatio.major(of: whole) + SharpitRatio.minor(of: whole) - whole) < 0.01)
    #expect(SharpitRatio.major(of: whole) > SharpitRatio.minor(of: whole))
}

// MARK: - Typography

@Test func trackingIsRelativeToFontSize() {
    // CSS tracking is in em; SwiftUI's is absolute, so the ramp has to convert.
    #expect(SharpitTypography.tracking(em: -0.02, size: 20) == -0.4)
    #expect(SharpitTypography.verdictTracking == SharpitTypography.tracking(em: -0.02, size: 20))
}

@Test func labelsAreTrackedOutAndHeadingsAreTrackedIn() {
    #expect(SharpitTypography.labelTracking > 0)
    #expect(SharpitTypography.verdictTracking < 0)
    #expect(SharpitTypography.sectionTitleTracking < 0)
}

@Test func theRampResolvesWhetherOrNotTheBrandFacesAreEmbedded() {
    // The bundle may not carry Syne/Plex/JetBrains yet; the ramp must still produce a
    // font rather than trapping on a missing PostScript name.
    let styles = [
        SharpitTypography.verdict, SharpitTypography.pageTitle, SharpitTypography.sectionTitle,
        SharpitTypography.cardTitle, SharpitTypography.body, SharpitTypography.meta,
        SharpitTypography.label, SharpitTypography.instrument, SharpitTypography.data,
    ]
    #expect(styles.count == 9)
}

@Test func anUnembeddedFamilyResolvesToNil() {
    for family in [SharpitFontFamily.heading, .body, .data] where !family.isEmbedded {
        #expect(family.resolvedName(for: .bold) == nil || family.resolvedName(for: .regular) == nil)
    }
}
