import SwiftUI

/// Whether a control should treat the current touch as a press, or as a pan that started on it.
/// Mirrors UIScrollView’s touch slop: a finger that slid is not a tap.
nonisolated enum SharpitPress {
    /// Finger travel below this stays a tap.
    static let activationSlop: CGFloat = 12

    static func shouldActivate(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) < activationSlop
    }
}

extension EnvironmentValues {
    /// Set by day-swipe (and similar pans): child controls must not activate on lift.
    @Entry var sharpitSuppressesControlActivation: Bool = false
}

/// A tappable surface answers the finger: it sinks slightly while pressed and springs back
/// on release. Like a scroll view, a pan that starts on it does not activate — only a true tap
/// calls the action (SwiftUI’s default `Button` would still fire after `allowsHitTesting` flips).
struct SharpitPressableStyle: PrimitiveButtonStyle {
    static let pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        SharpitPressableBody(configuration: configuration)
    }
}

private struct SharpitPressableBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.sharpitSuppressesControlActivation) private var suppresses
    @Environment(\.isEnabled) private var isEnabled
    @State private var pressed = false

    var body: some View {
        configuration.label
            .scaleEffect(pressed ? SharpitPressableStyle.pressedScale : 1)
            .opacity(pressed ? 0.92 : 1)
            .animation(SharpitMotion.selection, value: pressed)
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        pressed = isEnabled
                            && !suppresses
                            && SharpitPress.shouldActivate(translation: value.translation)
                    }
                    .onEnded { value in
                        pressed = false
                        guard isEnabled, !suppresses else { return }
                        guard SharpitPress.shouldActivate(translation: value.translation) else { return }
                        configuration.trigger()
                    }
            )
    }
}

extension PrimitiveButtonStyle where Self == SharpitPressableStyle {
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
