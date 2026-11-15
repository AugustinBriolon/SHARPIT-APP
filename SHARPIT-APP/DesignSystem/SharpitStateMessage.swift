import SwiftUI

/// A screen that could not show what it was asked for — no network, a read that failed, a thing
/// that no longer exists, a session to renew — or that simply holds nothing yet.
///
/// Clinique's state page (`docs/adr/0035`): the sheet's white under a wash in the state's tone,
/// an open ring around a quiet glyph — a ring that did not close, the app's own mark for
/// « not there » — what happened as a title, what to do in a sentence, and one ink button. Shown
/// before `RootView` too (the account gate), where no app tint reaches.
struct SharpitStateMessage: View {
    /// What kind of state this is: its wash and the hue of its ring.
    enum Kind: Equatable {
        case empty
        case offline
        case failed
        case notFound
        case session

        var wash: CliniqueWash {
            switch self {
            case .empty, .notFound: .neutral
            case .offline, .failed: .watch
            case .session: .coach
            }
        }

        var hue: Color {
            switch self {
            case .empty: SharpitColor.outline
            case .offline, .failed: SharpitColor.statusWatchMark
            case .notFound: SharpitColor.pillarSleep
            case .session: SharpitColor.pillarCoach
            }
        }

        /// How much of the ring is drawn: never closed.
        var arc: Double {
            switch self {
            case .empty: 1
            case .offline: 0.62
            case .failed: 0.78
            case .notFound: 0.5
            case .session: 0.86
            }
        }
    }

    let title: String
    let symbol: String
    var detail: String?
    var retry: (() -> Void)?
    var kind: Kind = .empty
    /// False inside a screen that already carries its own sheet and wash.
    var showsBackground = true

    @State private var isDrawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            emblem
                .padding(.bottom, 22)
            Text(title)
                .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title))
                .tracking(-0.5)
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .lineSpacing(3)
                    .foregroundStyle(SharpitColor.slate)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if let retry {
                Button(action: retry) { Text("Réessayer").frame(maxWidth: 240) }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                    .padding(.top, 26)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) {
            if showsBackground {
                ZStack(alignment: .top) {
                    SharpitColor.card
                    LinearGradient(colors: [kind.wash.color, SharpitColor.card], startPoint: .top, endPoint: .bottom)
                        .frame(height: 300)
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { isDrawn = true }
        }
    }

    /// The open ring and its glyph.
    private var emblem: some View {
        ZStack {
            Circle().stroke(SharpitColor.divider, lineWidth: 5)
            Circle()
                .trim(from: 0, to: isDrawn ? kind.arc : 0)
                .stroke(kind.hue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(SharpitColor.foreground)
        }
        .frame(width: 92, height: 92)
        .accessibilityHidden(true)
    }
}

extension SharpitStateMessage {
    /// The message alone, for a screen that already draws its sheet and its wash.
    func embedded() -> SharpitStateMessage {
        var copy = self
        copy.showsBackground = false
        return copy
    }

    /// The token was refused: only signing in again helps, so there is nothing to retry.
    static func sessionExpired() -> SharpitStateMessage {
        SharpitStateMessage(
            title: String(localized: "Session expirée"),
            symbol: "person.crop.circle.badge.exclamationmark",
            detail: String(localized: "Reconnecte-toi pour continuer."),
            kind: .session
        )
    }

    /// A read that failed, in the server's or the guidance's words; no network reads as such.
    static func failed(_ message: String, retry: (() -> Void)? = nil) -> SharpitStateMessage {
        let isOffline = message == SharpitErrorGuidance.offline
        return SharpitStateMessage(
            title: isOffline ? String(localized: "Pas de connexion") : String(localized: "Lecture impossible"),
            symbol: isOffline ? "wifi.slash" : "exclamationmark.triangle",
            detail: isOffline ? String(localized: "Vérifie ton réseau, puis réessaie. Ce que tu as déjà lu reste là.") : message,
            retry: retry,
            kind: isOffline ? .offline : .failed
        )
    }

    /// The thing asked for is gone or never was — the app's « 404 ».
    static func notFound(_ title: String, detail: String, retry: (() -> Void)? = nil) -> SharpitStateMessage {
        SharpitStateMessage(title: title, symbol: "questionmark", detail: detail, retry: retry, kind: .notFound)
    }
}
