import SwiftUI

/// Corner radii derived from the exported brand radius, mirroring the `--radius-analysis*`
/// scale in `globals.css`.
enum SharpitRadius {
    /// `--radius-analysis-sm`
    static let small = SharpitTokens.radius * 0.5
    /// `--radius-analysis` — the default panel.
    static let panel = SharpitTokens.radius * 0.875
    /// `--radius-analysis-lg` — alt panels and the ink band.
    static let panelLarge = SharpitTokens.radius * 1.125
}

/// The surfaces of the instrument-editorial system.
///
/// A surface separates itself from the canvas by luminosity and, on light, by a soft
/// neutral shadow — not by a hairline border. The web draws a 1px border; the app stopped
/// (ADR 0002 in this repository): on a phone the outline of every row read as a form grid, and
/// Apple's own grouped surfaces lift instead of outlining.
enum SharpitSurfaceStyle {
    /// `analysis-panel` — the default content surface.
    case panel
    /// `analysis-panel-alt` — a quieter alternate, for nested or selected blocks. It stays
    /// flat: it reads as set into the page, which is what a selection should look like.
    case panelAlt
    /// `chip-surface` — compact controls and signal cells.
    case chip
    /// `surface-ink` — the inverted band: Forest on light, Lime on dark.
    case ink

    func fill(at elevation: SharpitElevationLevel) -> Color {
        switch (self, elevation) {
        case (.panel, .sheet), (.chip, .sheet): SharpitElevatedColor.panelOnSheet
        case (.panel, .base): SharpitColor.analysisSurface
        case (.panelAlt, _): SharpitColor.analysisSurfaceAlt
        case (.chip, .base): SharpitColor.chipSurface
        case (.ink, _): SharpitColor.inkSurface
        }
    }

    var shadow: SharpitShadowStyle? {
        switch self {
        case .panel, .ink: .panel
        case .chip: .control
        case .panelAlt: nil
        }
    }

    var radius: CGFloat {
        switch self {
        case .panel: SharpitRadius.panel
        case .panelAlt, .ink: SharpitRadius.panelLarge
        case .chip: SharpitRadius.small
        }
    }

    /// The color text takes when it sits on this surface.
    var foreground: Color {
        switch self {
        case .panel, .panelAlt, .chip: SharpitColor.cardForeground
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

    /// Applies the signature high-precision specular top-edge light highlight on panel cards.
    func sharpitCardSpecularBorder(radius: CGFloat = SharpitRadius.panel) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.06),
                            Color.black.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
    }
}

