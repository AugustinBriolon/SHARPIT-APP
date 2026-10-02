import AuthenticationServices
import SwiftUI

/// Height shared by both providers' buttons, so they read as one pair.
enum SharpitSocialSignIn {
    static let buttonHeight: CGFloat = 50
}

/// Apple's own button (HIG, App Review 4.8): black on light, white on dark, title localized by
/// the system. It only draws and forwards the tap; Clerk runs the authorization itself.
struct SharpitAppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let action: () -> Void

    var body: some View {
        AppleIDButton(style: colorScheme == .dark ? .white : .black, action: action)
            // The style is fixed when the button is made, so a theme change makes a new one.
            .id(colorScheme)
            .frame(maxWidth: .infinity)
            .frame(height: SharpitSocialSignIn.buttonHeight)
            .accessibilityLabel("Continuer avec Apple")
    }
}

private struct AppleIDButton: UIViewRepresentable {
    let style: ASAuthorizationAppleIDButton.Style
    let action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: style)
        button.cornerRadius = SharpitTokens.radius
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

/// Google's button in its branding colours, set against Apple's: the dark theme where Apple's is
/// black, the light theme where it is white — same shape, height and type, the official « G ».
struct SharpitGoogleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let action: () -> Void

    private var isDark: Bool { colorScheme == .dark }
    // Google's published theme values (developers.google.com/identity/branding-guidelines).
    private var fill: Color { isDark ? .white : Color(red: 0x13 / 255, green: 0x13 / 255, blue: 0x14 / 255) }
    private var stroke: Color {
        isDark ? Color(red: 0x74 / 255, green: 0x77 / 255, blue: 0x75 / 255) : Color(red: 0x8E / 255, green: 0x91 / 255, blue: 0x8F / 255)
    }
    private var title: Color {
        isDark ? Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255) : Color(red: 0xE3 / 255, green: 0xE3 / 255, blue: 0xE3 / 255)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image("GoogleG")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .accessibilityHidden(true)
                Text("Continuer avec Google")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: SharpitSocialSignIn.buttonHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SharpitTokens.radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.sharpitPressable)
    }
}
