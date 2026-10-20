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
        // The system's layout, the brand's voice: the ink tile, SharpIt's type and its button —
        // shown before `RootView` too (the account gate), where no app tint reaches.
        ContentUnavailableView {
            VStack(spacing: SharpitSpacing.md) {
                SharpitIconTile(symbol: symbol, size: 56)
                Text(title)
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
            }
        } description: {
            if let detail {
                Text(detail)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        } actions: {
            if let retry {
                SharpitPrimaryButton(title: String(localized: "Réessayer"), style: .secondary, action: retry)
                    .frame(maxWidth: 220)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharpitCanvasBackground())
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
