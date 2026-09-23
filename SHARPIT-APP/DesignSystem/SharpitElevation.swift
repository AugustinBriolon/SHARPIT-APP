import SwiftUI
import UIKit

/// How far a screen sits above the canvas. A sheet is one level up, and the surfaces
/// inside it have to step up with it or they sink into its background.
enum SharpitElevationLevel: Sendable {
    case base
    case sheet
}

extension EnvironmentValues {
    @Entry var sharpitElevation: SharpitElevationLevel = .base
}

/// Colors for raised layers, derived from the generated tokens rather than added to them.
///
/// The web has no sheet, so it exports no sheet color. On dark the page canvas is close to
/// black, and a sheet drawn in it read as a black hole; the elevated layer takes the card
/// tone instead, and the panels on it lift once more by mixing in a little foreground.
nonisolated enum SharpitElevatedColor {
    /// Sheet background: the canvas on light, the card tone on dark — never black.
    static let sheet = adaptive(light: SharpitColor.background, dark: SharpitColor.card)

    /// Behind an inset-grouped list: one step darker than the cells on light, as iOS's own
    /// grouped background is, so a white row reads as a row. The page canvas is too close to
    /// white for that (1.03:1). On dark the order flips — cells lift, the canvas stays deep.
    static let groupedCanvas = adaptive(light: SharpitColor.muted, dark: SharpitColor.background)

    /// A panel inside a sheet.
    static let panelOnSheet = adaptive(
        light: SharpitColor.analysisSurface,
        dark: SharpitColor.card,
        darkLift: 0.06
    )

    /// The resting pill of a segmented control: white on light, a lifted track on dark.
    static let control = adaptive(
        light: SharpitColor.chipSurface,
        dark: SharpitColor.analysisBorder
    )

    /// `darkLift` mixes that fraction of the foreground into the dark tone.
    static func adaptive(light: Color, dark: Color, darkLift: CGFloat = 0) -> Color {
        let lightColor = UIColor(light)
        let darkColor = UIColor(dark)
        let foreground = UIColor(SharpitColor.foreground)
        return Color(uiColor: UIColor { traits in
            guard traits.userInterfaceStyle == .dark else {
                return lightColor.resolvedColor(with: traits)
            }
            let base = darkColor.resolvedColor(with: traits)
            guard darkLift > 0 else { return base }
            return mix(base, foreground.resolvedColor(with: traits), by: darkLift)
        })
    }

    private static func mix(_ base: UIColor, _ other: UIColor, by fraction: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        base.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * fraction,
            green: g1 + (g2 - g1) * fraction,
            blue: b1 + (b2 - b1) * fraction,
            alpha: a1
        )
    }
}

/// Soft neutral shadows, Apple-like: a tight contact shadow plus a wide ambient one.
///
/// Light only. On the dark canvas a black shadow is invisible at best and muddy at worst,
/// so dark separates layers through luminosity alone. Never tinted — a colored glow is
/// forbidden on both platforms.
enum SharpitShadowStyle {
    /// Content panels and rows.
    case panel
    /// A raised control inside a panel — the selected pill of a segmented answer.
    case control

    fileprivate struct Layer {
        let opacity: Double
        let radius: CGFloat
        let y: CGFloat
    }

    fileprivate var layers: (contact: Layer, ambient: Layer) {
        switch self {
        case .panel:
            (Layer(opacity: 0.04, radius: 1, y: 1), Layer(opacity: 0.06, radius: 12, y: 4))
        case .control:
            (Layer(opacity: 0.08, radius: 1, y: 1), Layer(opacity: 0.08, radius: 4, y: 2))
        }
    }
}

private struct SharpitShadowModifier: ViewModifier {
    let style: SharpitShadowStyle
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
        } else {
            let layers = style.layers
            content
                .shadow(color: .black.opacity(layers.contact.opacity), radius: layers.contact.radius, y: layers.contact.y)
                .shadow(color: .black.opacity(layers.ambient.opacity), radius: layers.ambient.radius, y: layers.ambient.y)
        }
    }
}

private struct SharpitSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.sharpitElevation, .sheet)
            .presentationBackground(SharpitElevatedColor.sheet)
    }
}

extension View {
    /// Lifts a shape off the canvas. Apply it to the background shape, not to a view with
    /// text in it: a shadow on content is re-rendered with every glyph.
    func sharpitShadow(_ style: SharpitShadowStyle) -> some View {
        modifier(SharpitShadowModifier(style: style))
    }

    /// Every sheet goes through here, so none falls back to the system's black.
    func sharpitSheet() -> some View {
        modifier(SharpitSheetModifier())
    }
}
