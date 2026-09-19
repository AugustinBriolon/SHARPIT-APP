import SwiftUI

/// Liquid Glass, reserved for Apple chrome.
///
/// ADR-041 draws the line here: the tab bar, the navigation bar and toolbar controls stay
/// system material, while content surfaces use `sharpitSurface(_:)`. Glass behind a plate
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
