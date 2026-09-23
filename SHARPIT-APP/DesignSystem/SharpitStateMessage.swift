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
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let detail {
                Text(detail)
            }
        } actions: {
            if let retry {
                Button("Réessayer", action: retry)
                    .buttonStyle(.bordered)
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
            title: "Session expirée",
            symbol: "person.crop.circle.badge.exclamationmark",
            detail: "Reconnecte-toi pour continuer."
        )
    }

    static func failed(_ message: String, retry: (() -> Void)? = nil) -> SharpitStateMessage {
        SharpitStateMessage(
            title: "Lecture impossible",
            symbol: "exclamationmark.triangle",
            detail: message,
            retry: retry
        )
    }
}
