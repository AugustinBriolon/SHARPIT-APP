import SwiftUI

/// What a screen shows when it has nothing to draw: a session that ended, a read that
/// failed, a list with nothing in it.
///
/// The system's `ContentUnavailableView`, on the app canvas, so every screen says "nothing
/// here" the same way and a failure always offers the same way out (`docs/adr/0008`).
struct SharpitStateMessage: View {
    let title: String
    let symbol: String
    var detail: String?
    var retry: (() -> Void)?

    var body: some View {
        // Clinique's empty and failed states (`docs/adr/0035`): a quiet glyph, what happened as a
        // title, what to do in a sentence, and one outline button — shown before `RootView` too
        // (the account gate), where no app tint reaches.
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(SharpitColor.slate)
                .accessibilityHidden(true)
            Text(title)
                .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.slate)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let retry {
                Button(String(localized: "Réessayer"), action: retry)
                    .buttonStyle(CliniqueButtonStyle(kind: .outline))
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharpitColor.card)
    }
}

extension SharpitStateMessage {
    /// The token was refused: only signing in again helps, so there is nothing to retry.
    static func sessionExpired() -> SharpitStateMessage {
        SharpitStateMessage(
            title: String(localized: "Session expirée"),
            symbol: "person.crop.circle.badge.exclamationmark",
            detail: String(localized: "Reconnecte-toi pour continuer.")
        )
    }

    static func failed(_ message: String, retry: (() -> Void)? = nil) -> SharpitStateMessage {
        SharpitStateMessage(
            title: String(localized: "Lecture impossible"),
            symbol: "exclamationmark.triangle",
            detail: message,
            retry: retry
        )
    }
}
