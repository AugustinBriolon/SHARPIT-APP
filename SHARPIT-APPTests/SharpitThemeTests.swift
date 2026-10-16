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

@Test func canvasIsCoolOffWhiteOnLightAndNearBlackOnDark() {
    #expect(hex(SharpitColor.background) == "#f7f8fa")
    #expect(hex(SharpitColor.background, style: .dark) == "#0b0b0c")
}

@Test func cardsArePureWhiteOnLight() {
    #expect(hex(SharpitColor.card) == "#ffffff")
    #expect(hex(SharpitColor.card, style: .dark) == "#161618")
}

@Test func inkIsNearBlack() {
    #expect(hex(SharpitColor.foreground) == "#0e0e0e")
    #expect(hex(SharpitColor.primary) == "#0e0e0e")
}

@Test func highlightIsLimeInBothThemes() {
    #expect(hex(SharpitColor.highlight) == "#cdf21e")
    #expect(hex(SharpitColor.highlight, style: .dark) == "#cdf21e")
}

@Test func iconTilesAreInkOnLightAndGraphiteOnDark() {
    #expect(hex(SharpitColor.inkSurface) == "#0e0e0e")
    #expect(hex(SharpitColor.inkSurface, style: .dark) == "#2a2a2e")
    #expect(hex(SharpitColor.inkAccent) == "#cdf21e")
}

@Test func insetGroupAndTrackSurfacesAreExported() {
    #expect(hex(SharpitColor.insetGroup) == "#f4f4f2")
    #expect(hex(SharpitColor.track) == "#ebebeb")
    #expect(hex(SharpitColor.chipSurface) == "#f2f2f2")
}

@Test func hairlineBordersCarryTheirAlpha() {
    #expect(channels(SharpitColor.analysisBorder).alpha < 1)
}

@Test func everySportSharesTheSameMonochromeTone() {
    for type in [V1ActivityType.run, .bike, .swim, .strength] {
        #expect(hex(SharpitSportTone.accent(for: type)) == hex(SharpitColor.foreground))
        #expect(
            hex(SharpitSportTone.accent(for: type), style: .dark)
                == hex(SharpitColor.foreground, style: .dark)
        )
        #expect(hex(SharpitSportTone.tile(for: type)) == hex(SharpitColor.inkSurface))
    }
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

@Test func regularColumnCapsAnIPadWindow() {
    #expect(SharpitSpacing.regularColumn == 760)
}

@Test func cardRadiusMatchesThePanelRadius() {
    #expect(SharpitSpacing.cardRadius == SharpitRadius.panel)
    #expect(SharpitTokens.radius == 16)
}

@Test func radiiNestFromCardToChip() {
    // Card 28 > inset group 24 > row 18 > control 16 > tile 14 > chip 8: each nested
    // corner is tighter than the one around it, as in the references.
    let ladder = [
        SharpitRadius.panel, SharpitRadius.inset, SharpitRadius.row,
        SharpitRadius.control, SharpitRadius.tile, SharpitRadius.small,
    ]
    #expect(ladder == [28, 24, 18, 16, 14, 8])
    #expect(SharpitRadius.panelLarge == SharpitRadius.panel)
}

@Test func cardGeometryFollowsTheReferences() {
    #expect(SharpitSpacing.cardPadding == 24)
    #expect(SharpitSpacing.insetPadding == 12)
    #expect(SharpitSpacing.rowGap == 8)
    #expect(SharpitSpacing.controlHeight == 52)
    #expect(SharpitSpacing.rowHeight == 56)
    #expect(SharpitTokens.tileSize == 44)
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

@Test func figuresAreHeavierThanTitles() {
    // The references hang on heavy figures: the hero number outweighs every title.
    #expect(SharpitFontWeight.heavy.uiKit.rawValue > SharpitFontWeight.bold.uiKit.rawValue)
    #expect(SharpitTypography.heroScoreTracking < SharpitTypography.pageTitleTracking)
}

// MARK: - Elevation

private func luminance(_ color: Color, style: UIUserInterfaceStyle) -> CGFloat {
    let (red, green, blue, _) = channels(color, style: style)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
}

/// A sheet on dark took the system's black; it now sits one step above the canvas.
@Test func aSheetIsNeverBlackAndSitsAboveTheCanvasOnDark() {
    #expect(hex(SharpitElevatedColor.sheet, style: .dark) == hex(SharpitColor.card, style: .dark))
    #expect(
        luminance(SharpitElevatedColor.sheet, style: .dark)
            > luminance(SharpitColor.background, style: .dark)
    )
    #expect(hex(SharpitElevatedColor.sheet) == hex(SharpitColor.background))
}

/// Panels inside a sheet must lift again, or they sink into the sheet's own tone.
@Test func aPanelOnASheetLiftsAboveTheSheetOnDark() {
    #expect(
        luminance(SharpitElevatedColor.panelOnSheet, style: .dark)
            > luminance(SharpitElevatedColor.sheet, style: .dark)
    )
    #expect(hex(SharpitElevatedColor.panelOnSheet) == hex(SharpitColor.analysisSurface))
}

@Test func onlyCardsCastAShadow() {
    #expect(SharpitSurfaceStyle.panel.shadow != nil)
    #expect(SharpitSurfaceStyle.chip.shadow == nil)
    #expect(SharpitSurfaceStyle.panelAlt.shadow == nil)
    #expect(SharpitSurfaceStyle.row.shadow == nil)
}

@Test func aRowSitsWhiteInsideTheGreyGroup() {
    #expect(hex(SharpitElevatedColor.row) == "#ffffff")
    #expect(
        luminance(SharpitElevatedColor.row, style: .dark)
            > luminance(SharpitColor.insetGroup, style: .dark)
    )
}

/// The Human Interface Guidelines' floor for anything tappable (`docs/adr/0008`).
@Test func aTappableTargetIsNeverSmallerThanFortyFourPoints() {
    #expect(SharpitSpacing.minimumTouchTarget >= 44)
}
