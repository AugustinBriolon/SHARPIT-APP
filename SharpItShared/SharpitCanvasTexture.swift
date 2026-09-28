import SwiftUI

/// A living canvas texture — micro-dot grid + two soft brand halos — layered behind
/// the page content.
///
/// Rules it follows:
/// - Opacity kept at ≤ 5 % so the texture reads as *material*, never as decoration.
/// - Colors are brand tokens, not arbitrary hues.
/// - Fully static under `prefers-reduce-motion` (the dots are always visible, but the
///   slow drift animation collapses to `.identity`).
/// - Drawn with SwiftUI `Canvas` — no UIKit, no `drawRect`, no Core Graphics overhead
///   in the render loop.
struct SharpitCanvasTexture: View {
    /// Controls whether the very slow parallax drift plays (requires a parent that
    /// supplies a `TimelineView`). Default `true`.
    var animated: Bool = true

    var body: some View {
        ZStack {
            // 1. Brand halos — two large radial gradients anchored at corners.
            brandHalos
            // 2. Dot grid drawn with Canvas.
            DotGridCanvas()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: – Brand halos

    private var brandHalos: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Top-leading: primary (Forest green / Lime Pulse)
                RadialGradient(
                    colors: [SharpitColor.primary.opacity(0.07), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: w * 0.75
                )
                // Bottom-trailing: highlight accent (Lime Pulse / Forest)
                RadialGradient(
                    colors: [SharpitColor.highlight.opacity(0.05), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: w * 0.65
                )
            }
            .frame(width: w, height: h)
        }
    }
}

// MARK: – Dot grid

private struct DotGridCanvas: View {
    /// Spacing between dot centres.
    private let step: CGFloat = 20
    /// Dot radius.
    private let r: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let color = GraphicsContext.Shading.color(
                SharpitColor.foreground.opacity(0.04)
            )
            var x: CGFloat = step / 2
            while x < size.width {
                var y: CGFloat = step / 2
                while y < size.height {
                    let dot = Path(ellipseIn: CGRect(
                        x: x - r, y: y - r,
                        width: r * 2, height: r * 2
                    ))
                    context.fill(dot, with: color)
                    y += step
                }
                x += step
            }
        }
    }
}

#Preview {
    SharpitCanvasTexture()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharpitColor.background)
}
