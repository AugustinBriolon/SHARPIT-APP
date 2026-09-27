import ClerkKit
import SwiftUI

/// The athlete's face in the navigation bar, opening Paramètres — the pattern of the App Store
/// and Fitness. Their Clerk photo when they set one, else their initials on a quiet disc: a
/// generic person glyph would say "someone", initials say "you".
struct AccountAvatarButton: View {
    let action: () -> Void

    // Declared bare and set in `init`: the attribute cannot take `relativeTo:` without a value.
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat = 32, action: @escaping () -> Void) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            AccountAvatar(size: size)
        }
        .buttonStyle(.sharpitPressable)
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
            Group {
                if let initials = AccountInitials.from(
                    first: clerk.user?.firstName,
                    last: clerk.user?.lastName,
                    email: clerk.user?.primaryEmailAddress?.emailAddress
                ) {
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                }
            }
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
    /// « Augustin Briolon » → « AB »; one name → its first letter; no name → the e-mail's first
    /// letter; nothing at all → nil, and the disc shows a person instead of a question mark.
    static func from(first: String?, last: String?, email: String? = nil) -> String? {
        let letters = [first, last]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces).first }
            .map { String($0).uppercased() }
        if !letters.isEmpty { return letters.joined() }
        return email?.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() }
    }
}
