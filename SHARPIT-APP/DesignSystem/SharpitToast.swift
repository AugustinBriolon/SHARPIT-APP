import SwiftUI

/// One line, from the top: SHARPIT's only interruption for a background event — a sync
/// starting, failing, or a health send going through.
///
/// A single slot, not a stack (`docs/adr/0008`): two things happening at once is rare enough
/// that showing the latest is enough, and a queue of toasts reads as noise on a screen built
/// around one causal column. A toast never carries information the athlete must act on —
/// that stays a screen or a footer — it only says something is in progress or just failed.
@MainActor
@Observable
final class SharpitToastCenter {
    struct Toast: Identifiable, Equatable {
        let id: UUID
        var message: String
        var symbol: String
        var tone: SharpitToastTone
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    /// Shows a toast and returns a token. A caller keeps the token and passes it back to
    /// `dismiss(_:)`, so it only ever clears the toast it put up — never one a later event
    /// already replaced it with.
    @discardableResult
    func show(
        _ message: String,
        symbol: String,
        tone: SharpitToastTone = .syncing,
        autoDismissAfter: TimeInterval? = 2.5
    ) -> UUID {
        dismissTask?.cancel()
        let id = UUID()
        current = Toast(id: id, message: message, symbol: symbol, tone: tone)
        if let autoDismissAfter {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(autoDismissAfter))
                guard !Task.isCancelled else { return }
                self?.dismiss(id)
            }
        }
        return id
    }

    /// Clears the toast only when `token` is still the one showing.
    func dismiss(_ token: UUID) {
        guard current?.id == token else { return }
        dismissTask?.cancel()
        current = nil
    }

    /// Clears whatever is showing, regardless of who put it up — a tap on the toast itself.
    func dismissCurrent() {
        dismissTask?.cancel()
        current = nil
    }
}

enum SharpitToastTone: Equatable {
    case syncing
    case success
    case error

    var symbolColor: Color {
        switch self {
        case .syncing, .success: SharpitColor.primary
        case .error: SharpitColor.signalRisk
        }
    }

    var badgeBackground: Color {
        switch self {
        case .syncing: SharpitColor.primary.opacity(0.12)
        case .success: SharpitColor.primary.opacity(0.16)
        case .error: SharpitColor.signalRisk.opacity(0.16)
        }
    }

    var rimColor: Color {
        switch self {
        case .syncing: SharpitColor.primary.opacity(0.2)
        case .success: SharpitColor.primary.opacity(0.4)
        case .error: SharpitColor.signalRisk.opacity(0.45)
        }
    }
}

/// The toast itself: a compact pill, never the width of the screen. The HIG's own banners —
/// an incoming call, a dropped connection — stay this size so they read as a passing event,
/// not a new screen the athlete has to dismiss.
private struct SharpitToastView: View {
    let toast: SharpitToastCenter.Toast

    var body: some View {
        HStack(spacing: SharpitSpacing.xs) {
            ZStack {
                Circle()
                    .fill(toast.tone.badgeBackground)
                    .frame(width: 20, height: 20)

                if toast.tone == .syncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: toast.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(toast.tone.symbolColor)
                }
            }

            Text(toast.message)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, SharpitSpacing.md)
        .padding(.vertical, SharpitSpacing.sm)
        // The one exception to "glass is Apple chrome only" (`docs/adr/0008` narrows
        // `docs/adr/0002`... this stays content, not the system's): a toast is transient,
        // system-adjacent chrome by nature, the same register as the tab bar and the nav
        // bar, not a card the athlete reads.
        .sharpitGlassCapsule()
        .overlay(
            Capsule()
                .strokeBorder(toast.tone.rimColor, lineWidth: 1)
        )
        .sharpitShadow(.panel)
        .accessibilityElement(children: .combine)
    }
}

/// Hosts the one toast the app shows, pinned under the status bar regardless of which tab is
/// in front. `RootView` mounts this once, above the `TabView`.
struct SharpitToastHost: View {
    let center: SharpitToastCenter

    var body: some View {
        VStack(spacing: 0) {
            if let toast = center.current {
                SharpitToastView(toast: toast)
                    .padding(.top, SharpitSpacing.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.dismissCurrent() }
            }
            Spacer(minLength: 0)
        }
        .animation(SharpitMotion.reveal, value: center.current)
        .allowsHitTesting(center.current != nil)
    }
}

extension View {
    /// Bridges a `ProviderSyncStore` to the app's one toast slot: visible while a pull is
    /// under way or just failed, silent the rest of the time — a settled sync is not news,
    /// only a change in progress is (`docs/adr/0008`).
    func sharpitSyncToast(_ sync: ProviderSyncStore?) -> some View {
        modifier(SharpitSyncToastModifier(sync: sync))
    }
}

private struct SharpitSyncToastModifier: ViewModifier {
    let sync: ProviderSyncStore?

    @Environment(SharpitToastCenter.self) private var toastCenter
    @State private var token: UUID?

    func body(content: Content) -> some View {
        content.onChange(of: sync?.state) { oldState, state in
            switch state {
            case .syncing:
                token = toastCenter.show(
                    "Synchronisation…",
                    symbol: "arrow.triangle.2.circlepath",
                    tone: .syncing,
                    autoDismissAfter: nil
                )
            case .failed:
                token = toastCenter.show(
                    "Synchronisation impossible",
                    symbol: "exclamationmark.triangle.fill",
                    tone: .error,
                    autoDismissAfter: 3.5
                )
            case .idle:
                if oldState == .syncing {
                    token = toastCenter.show(
                        "Synchronisé",
                        symbol: "checkmark.circle.fill",
                        tone: .success,
                        autoDismissAfter: 2.0
                    )
                } else if let token {
                    toastCenter.dismiss(token)
                    self.token = nil
                }
            case nil:
                if let token { toastCenter.dismiss(token) }
                token = nil
            }
        }
    }
}
