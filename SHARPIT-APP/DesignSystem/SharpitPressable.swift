import SwiftUI

/// A tappable surface answers the finger: it sinks slightly while pressed and springs back
/// on release. `.plain` gave no feedback at all, so cards that open something looked
/// exactly like cards that do not.
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

/// A compact score ring — a readout beside its number, never the hero of a screen.
struct SharpitScoreRing: View {
    let fraction: Double
    let tone: Color
    var lineWidth: CGFloat = 4

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(SharpitColor.analysisGrid, lineWidth: lineWidth)
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
