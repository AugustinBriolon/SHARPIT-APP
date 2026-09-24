import ClerkKit
import SwiftUI

/// The athlete's face in the navigation bar, opening Paramètres — the pattern of the App Store
/// and Fitness. Their Clerk photo when they set one, else their initials on a quiet disc: a
/// generic person glyph would say "someone", initials say "you".
struct AccountAvatarButton: View {
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 32

    var body: some View {
        Button(action: action) {
            AccountAvatar(size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paramètres")
        .accessibilityHint("Compte, abonnement et réglages")
    }
}

/// The avatar itself, for the button and for the Compte page.
struct AccountAvatar: View {
    let size: CGFloat

    @Environment(Clerk.self) private var clerk

    var body: some View {
        Group {
            if let url = photoURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsDisc
                }
            } else {
                initialsDisc
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initialsDisc: some View {
        ZStack {
            Circle().fill(SharpitColor.primary.opacity(0.14))
            Text(AccountInitials.from(first: clerk.user?.firstName, last: clerk.user?.lastName))
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(SharpitColor.primary)
        }
    }

    /// Clerk serves a generated image even without an upload; only a photo the athlete chose
    /// replaces the initials.
    private var photoURL: URL? {
        guard let user = clerk.user, user.hasImage else { return nil }
        return URL(string: user.imageUrl)
    }
}

nonisolated enum AccountInitials {
    /// « Augustin Briolon » → « AB »; one name → its first letter; nothing → « ? ».
    static func from(first: String?, last: String?) -> String {
        let letters = [first, last]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces).first }
            .map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
