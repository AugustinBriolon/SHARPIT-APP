import SwiftUI

/// A tappable surface answers the finger: it sinks slightly while pressed and springs back
/// on release. `.plain` gave no feedback at all, so cards that open something looked
/// exactly like cards that do not.
///
/// Stays a `ButtonStyle` (not `PrimitiveButtonStyle` + drag): ScrollView must be able to
/// take over when the finger slides, as UIScrollView does with `canCancelContentTouches`.
struct SharpitPressableStyle: ButtonStyle {
    static let pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(SharpitMotion.selection, value: configuration.isPressed)
            .contentShape(.rect)
    }
}

extension ButtonStyle where Self == SharpitPressableStyle {
    /// For a card, row or tile that opens or changes something.
    static var sharpitPressable: SharpitPressableStyle { SharpitPressableStyle() }
}

/// A score ring: a round-capped arc on the track — compact beside a number, or thick around
/// a countdown (ADR-085). Lime is the default tone.
struct SharpitScoreRing: View {
    let fraction: Double
    var tone: Color = SharpitColor.highlight
    var lineWidth: CGFloat = 4

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(SharpitColor.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(tone, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            SharpitMotion.run(SharpitMotion.gaugeFill) {
                shown = min(max(fraction, 0), 1)
            }
        }
        .onChange(of: fraction) { _, new in
            SharpitMotion.run(SharpitMotion.gaugeFill) {
                shown = min(max(new, 0), 1)
            }
        }
        .accessibilityHidden(true)
    }
}
