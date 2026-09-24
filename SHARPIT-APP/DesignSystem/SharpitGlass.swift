import SwiftUI

/// Liquid Glass, reserved for Apple chrome.
///
/// ADR-041 draws the line here: the tab bar, the navigation bar, toolbar controls and the
/// controls floating over scrolled content (the coach's composer) are glass, while content
/// surfaces use `sharpitSurface(_:)`. Glass behind a plate
/// made the brand colors translucent and put a third surface language on screen.
extension View {
    /// A toolbar-level control — the only place content-adjacent glass is allowed.
    @ViewBuilder
    func sharpitGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// A circular toolbar-level control in liquid glass.
    @ViewBuilder
    func sharpitGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .circle)
        } else {
            background(.ultraThinMaterial, in: Circle())
        }
    }
}

extension View {
    /// A control floating over content the athlete scrolls under — the coach's composer, as
    /// Messages draws its own. Interactive glass answers the finger; a tint marks the one
    /// action that is live. Falls back to the flat fill it replaces before iOS 26.
    @ViewBuilder
    func sharpitGlassControl<S: Shape>(in shape: S, tint: Color? = nil, fallback: Color) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            background(tint ?? fallback, in: shape)
        }
    }
}

extension View {
    /// A screen's docked action, floating over the content scrolled under it: glass on
    /// iOS 26 and later — prominent and tinted for the forward action — bordered before.
    @ViewBuilder
    func sharpitGlassButton(prominent: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

/// Groups glass controls so they share one sampling region and blend as they move —
/// a button sliding in beside the field melts out of it rather than popping.
struct SharpitGlassGroup<Content: View>: View {
    var spacing: CGFloat = SharpitSpacing.xs
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

struct ScrollUnderGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        } else {
            content
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
    }
}

struct LiquidNavChrome: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
