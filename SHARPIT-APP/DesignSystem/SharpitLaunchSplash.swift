import SwiftUI

/// The cold launch's loading screen (`LaunchCurtain`): the app icon's mark, drawn from the first
/// frame exactly where the system launch screen put it (`LaunchMark`, screen centre), breathing
/// while Résumé is read. It leaves by growing a touch as it fades, onto Résumé.
struct SharpitLaunchSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let markSize: CGFloat = 52

    var body: some View {
        ZStack {
            SharpitCanvasBackground()
            Self.mark
                .symbolEffect(.breathe, isActive: !reduceMotion)
        }
        // The screen's centre, not the safe area's: the launch screen's image sits there.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement")
    }

    /// Also rendered into the `LaunchMark` asset, so the system launch screen draws the same pixels.
    static var mark: some View {
        Image(systemName: "circle.hexagonpath.fill")
            .font(.system(size: markSize, weight: .regular))
            .foregroundStyle(SharpitColor.brandMarkGradient)
    }
}

extension AnyTransition {
    /// The splash leaving: it fades while growing a touch, so Résumé seems to come forward.
    static var sharpitLaunchExit: AnyTransition {
        .asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.08)))
    }
}

#Preview {
    SharpitLaunchSplash()
}
