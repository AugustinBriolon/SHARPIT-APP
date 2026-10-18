import SwiftUI

/// The cold launch's loading screen (`LaunchCurtain`): the app icon's mark, drawn from the first
/// frame exactly where the system launch screen put it (`LaunchMark`, screen centre), breathes;
/// a fine lime arc circles it only once the wait is long enough to need saying, so a fast launch
/// shows the mark alone. It leaves by growing slightly as it fades, onto Résumé.
struct SharpitLaunchSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arcIsIn = false

    private static let markSize: CGFloat = 52
    private static let ringSize: CGFloat = 104
    private static let ringWidth: CGFloat = 2
    /// Below this a wait reads as instant: no arc.
    private static let arcDelay: Duration = .milliseconds(450)
    private static let turn: TimeInterval = 1.4

    var body: some View {
        ZStack {
            SharpitCanvasBackground()
            ZStack {
                arc
                    .opacity(arcIsIn ? 1 : 0)
                Self.mark
                    .symbolEffect(.breathe, isActive: !reduceMotion)
            }
        }
        // The screen's centre, not the safe area's: the launch screen's image sits there.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement")
        .task { await arrive() }
    }

    /// Also rendered into the `LaunchMark` asset, so the system launch screen draws the same pixels.
    static var mark: some View {
        Image(systemName: "circle.hexagonpath.fill")
            .font(.system(size: markSize, weight: .regular))
            .foregroundStyle(SharpitColor.brandMarkGradient)
    }

    /// A short lime arc on a hairline track, turning steadily — the only motion that says « wait ».
    private var arc: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let angle = seconds.truncatingRemainder(dividingBy: Self.turn) / Self.turn * 360
            ZStack {
                Circle()
                    .stroke(SharpitColor.border, lineWidth: Self.ringWidth)
                Circle()
                    .trim(from: 0, to: 0.18)
                    .stroke(SharpitColor.highlight, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: Self.ringSize, height: Self.ringSize)
        }
    }

    private func arrive() async {
        guard !reduceMotion else { return }
        try? await Task.sleep(for: Self.arcDelay)
        guard !Task.isCancelled else { return }
        SharpitMotion.run(SharpitMotion.fade) { arcIsIn = true }
    }
}

extension AnyTransition {
    /// The splash leaving: it fades while growing a touch, so Résumé seems to come forward.
    static var sharpitLaunchExit: AnyTransition {
        .asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.06)))
    }
}

#Preview {
    SharpitLaunchSplash()
}
