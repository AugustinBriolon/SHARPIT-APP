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
/// `design.md` is explicit: prefer a flat surface with a hairline border, and express
/// elevation through luminosity rather than heavy shadows. There are no gradients and no
/// drop shadows here on purpose — a panel separates itself from the canvas by being a
/// different lightness, exactly as it does on the web.
enum SharpitSurfaceStyle {
    /// `analysis-panel` — the default content surface.
    case panel
    /// `analysis-panel-alt` — a quieter alternate, for nested or secondary blocks.
    case panelAlt
    /// `chip-surface` — compact controls and signal cells.
    case chip
    /// `surface-ink` — the inverted band: Forest on light, Lime on dark.
    case ink

    var fill: Color {
        switch self {
        case .panel: SharpitColor.analysisSurface
        case .panelAlt: SharpitColor.analysisSurfaceAlt
        case .chip: SharpitColor.chipSurface
        case .ink: SharpitColor.inkSurface
        }
    }

    var stroke: Color {
        switch self {
        case .panel, .panelAlt: SharpitColor.analysisBorder
        case .chip: SharpitColor.analysisBorder.opacity(0.81)
        case .ink: .clear
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

    func body(content: Content) -> some View {
        content
            .foregroundStyle(style.foreground)
            .background(
                RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                    .fill(style.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                    .strokeBorder(style.stroke, lineWidth: SharpitStroke.hairline)
            )
    }
}

extension View {
    /// Applies an instrument surface: flat fill, hairline border, no shadow.
    func sharpitSurface(_ style: SharpitSurfaceStyle) -> some View {
        modifier(SharpitSurfaceModifier(style: style))
    }
}
