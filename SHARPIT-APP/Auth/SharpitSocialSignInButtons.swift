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

/// Google's button in its light theme, white in both appearances — same shape, height and type
/// as Apple's, with the official « G ».
struct SharpitGoogleSignInButton: View {
    let action: () -> Void

    // Google's published light theme (developers.google.com/identity/branding-guidelines).
    private let fill = Color.white
    private let stroke = Color(red: 0x74 / 255, green: 0x77 / 255, blue: 0x75 / 255)
    private let title = Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255)

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
