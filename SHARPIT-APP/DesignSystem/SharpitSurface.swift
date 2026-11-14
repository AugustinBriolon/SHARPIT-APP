import SwiftUI

/// Corner radii. The card comes from the Clinique shape tokens (SHARPIT-WEBAPP ADR-131); what
/// nests inside steps down from it, each corner tighter than the one around it.
enum SharpitRadius {
    /// Number chips and check boxes.
    static let small = SharpitTokens.chipRadius
    /// Cards (`--shape-card`, SHARPIT-WEBAPP ADR-131).
    static let panel = SharpitTokens.cardShapeRadius
    /// The ink band — same corner as a card.
    static let panelLarge = SharpitTokens.cardShapeRadius
    /// The grey group that holds rows.
    static let inset: CGFloat = 16
    /// A row inside an inset group.
    static let row: CGFloat = 14
    /// Icon tiles.
    static let tile: CGFloat = 10
    /// Buttons and segmented controls.
    static let control = SharpitTokens.pillShapeRadius
}

/// The surfaces of the Clinique system (SHARPIT-WEBAPP ADR-131, `docs/adr/0035`).
///
/// A screen is one sheet. A card is part of it: the sheet's colour inside a hairline, never a
/// shadow. Inside a card, rows read straight on it, split by lines.
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
        case (.panel, .base): SharpitColor.card
        case (.panelAlt, _): SharpitColor.tile
        case (.chip, .base): SharpitColor.tile
        case (.ink, _): SharpitColor.inkSurface
        // Rows read straight on their card: no second box inside a card.
        case (.row, _): .clear
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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // The corner is declared inside the fill so what sits within nests concentric to it,
        // while a nested surface's own fill follows the surface around it.
        content
            // What sits on ink reads the dark values of every token, so slate, tiles and status
            // marks stay legible on it in light mode too.
            .environment(\.colorScheme, style == .ink ? .dark : colorScheme)
            .foregroundStyle(style.foreground)
            .sharpitContainerCorner(style.radius)
            .background {
                if style == .panel {
                    // A card is part of the sheet: its colour, and a hairline where a shadow was
                    // (SHARPIT-WEBAPP ADR-131). Strokes keep a fixed shape.
                    RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                        .fill(style.fill(at: elevation))
                        .overlay(
                            RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                                .strokeBorder(SharpitColor.divider, lineWidth: 1)
                        )
                } else {
                    Color.clear.sharpitConcentricBackground(style.fill(at: elevation), minimum: style.radius)
                }
            }
    }
}

extension View {
    /// Applies a surface: a bordered card for a panel, a tonal fill for the others.
    func sharpitSurface(_ style: SharpitSurfaceStyle) -> some View {
        modifier(SharpitSurfaceModifier(style: style))
    }
}
