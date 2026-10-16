import SwiftUI

/// Corner radii, exported from the web geometry tokens (ADR-085).
enum SharpitRadius {
    /// Number chips and check boxes.
    static let small = SharpitTokens.chipRadius
    /// Cards.
    static let panel = SharpitTokens.cardRadius
    /// The ink band — same corner as a card.
    static let panelLarge = SharpitTokens.cardRadius
    /// The grey group that holds rows.
    static let inset = SharpitTokens.insetRadius
    /// A row inside an inset group.
    static let row = SharpitTokens.rowRadius
    /// Icon tiles.
    static let tile = SharpitTokens.tileRadius
    /// Buttons and segmented controls.
    static let control = SharpitTokens.radius
}

/// The surfaces of the Ink & Lime system (ADR-085).
///
/// A white card lifts off the cool canvas with one soft, wide shadow on light and by
/// luminosity on dark — never with a border. Inside a card, rows sit in a grey inset group.
enum SharpitSurfaceStyle {
    /// `analysis-panel` — the default content surface.
    case panel
    /// `inset-group` — the grey container that holds white rows inside a card. Flat.
    case panelAlt
    /// `chip-surface` — neutral chips, compact controls and signal cells. Flat.
    case chip
    /// `surface-ink` — ink on light, a lifted graphite on dark.
    case ink
    /// A white row inside an inset group. Flat.
    case row

    func fill(at elevation: SharpitElevationLevel) -> Color {
        switch (self, elevation) {
        case (.panel, .sheet), (.chip, .sheet): SharpitElevatedColor.panelOnSheet
        case (.panel, .base): SharpitColor.analysisSurface
        case (.panelAlt, _): SharpitColor.insetGroup
        case (.chip, .base): SharpitColor.chipSurface
        case (.ink, _): SharpitColor.inkSurface
        case (.row, _): SharpitElevatedColor.row
        }
    }

    var shadow: SharpitShadowStyle? {
        switch self {
        case .panel, .ink: .panel
        case .chip, .panelAlt, .row: nil
        }
    }

    var radius: CGFloat {
        switch self {
        case .panel, .ink: SharpitRadius.panel
        case .panelAlt: SharpitRadius.inset
        case .row: SharpitRadius.row
        case .chip: SharpitSpacing.chipRadius
        }
    }

    /// The color text takes when it sits on this surface.
    var foreground: Color {
        switch self {
        case .panel, .panelAlt, .chip, .row: SharpitColor.cardForeground
        case .ink: SharpitColor.inkSurfaceForeground
        }
    }
}

private struct SharpitSurfaceModifier: ViewModifier {
    let style: SharpitSurfaceStyle
    @Environment(\.sharpitElevation) private var elevation

    func body(content: Content) -> some View {
        content
            .foregroundStyle(style.foreground)
            .background {
                let shape = RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                if let shadow = style.shadow {
                    shape.fill(style.fill(at: elevation)).sharpitShadow(shadow)
                } else {
                    shape.fill(style.fill(at: elevation))
                }
            }
    }
}

extension View {
    /// Applies an instrument surface: tonal fill, soft shadow on light, no border.
    func sharpitSurface(_ style: SharpitSurfaceStyle) -> some View {
        modifier(SharpitSurfaceModifier(style: style))
    }
}

