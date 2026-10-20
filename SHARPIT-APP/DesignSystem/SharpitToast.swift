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
        var title: String?
        var avatarURL: URL?
        var accentColor: Color?
        var action: (@MainActor () -> Void)?
        var onDismiss: (@MainActor () -> Void)?

        var isDynamicNotification: Bool {
            title != nil || avatarURL != nil || action != nil
        }

        init(
            id: UUID = UUID(),
            message: String,
            symbol: String = "bell.fill",
            tone: SharpitToastTone = .syncing,
            title: String? = nil,
            avatarURL: URL? = nil,
            accentColor: Color? = nil,
            action: (@MainActor () -> Void)? = nil,
            onDismiss: (@MainActor () -> Void)? = nil
        ) {
            self.id = id
            self.message = message
            self.symbol = symbol
            self.tone = tone
            self.title = title
            self.avatarURL = avatarURL
            self.accentColor = accentColor
            self.action = action
            self.onDismiss = onDismiss
        }

        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.id == rhs.id &&
            lhs.message == rhs.message &&
            lhs.symbol == rhs.symbol &&
            lhs.tone == rhs.tone &&
            lhs.title == rhs.title &&
            lhs.avatarURL == rhs.avatarURL &&
            lhs.accentColor == rhs.accentColor
        }
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
        show(
            message: message,
            title: nil,
            symbol: symbol,
            tone: tone,
            avatarURL: nil,
            accentColor: nil,
            autoDismissAfter: autoDismissAfter,
            action: nil,
            onDismiss: nil
        )
    }

    /// Shows a rich Dynamic Island-style notification or toast.
    @discardableResult
    func show(
        message: String,
        title: String? = nil,
        symbol: String = "bell.fill",
        tone: SharpitToastTone = .syncing,
        avatarURL: URL? = nil,
        accentColor: Color? = nil,
        autoDismissAfter: TimeInterval? = 2.5,
        action: (@MainActor () -> Void)? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) -> UUID {
        dismissTask?.cancel()
        let previousDismiss = current?.onDismiss
        let id = UUID()
        current = Toast(
            id: id,
            message: message,
            symbol: symbol,
            tone: tone,
            title: title,
            avatarURL: avatarURL,
            accentColor: accentColor,
            action: action,
            onDismiss: onDismiss
        )
        previousDismiss?()

        if let autoDismissAfter {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(autoDismissAfter))
                guard !Task.isCancelled else { return }
                self?.dismiss(id)
            }
        }
        return id
    }

    /// Dynamic Island notification trigger matching expo-dynamic-notifications API.
    @discardableResult
    func trigger(
        title: String,
        message: String? = nil,
        symbol: String = "bell.fill",
        avatarURL: URL? = nil,
        accentColor: Color? = nil,
        tone: SharpitToastTone = .success,
        duration: TimeInterval? = 3.5,
        action: (@MainActor () -> Void)? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) -> UUID {
        show(
            message: message ?? "",
            title: title,
            symbol: symbol,
            tone: tone,
            avatarURL: avatarURL,
            accentColor: accentColor,
            autoDismissAfter: duration,
            action: action,
            onDismiss: onDismiss
        )
    }

    /// Convenience for string-based avatar URLs.
    @discardableResult
    func trigger(
        title: String,
        message: String? = nil,
        symbol: String = "bell.fill",
        avatar: String?,
        accentColor: Color? = nil,
        tone: SharpitToastTone = .success,
        duration: TimeInterval? = 3.5,
        action: (@MainActor () -> Void)? = nil,
        onDismiss: (@MainActor () -> Void)? = nil
    ) -> UUID {
        trigger(
            title: title,
            message: message,
            symbol: symbol,
            avatarURL: avatar.flatMap { URL(string: $0) },
            accentColor: accentColor,
            tone: tone,
            duration: duration,
            action: action,
            onDismiss: onDismiss
        )
    }

    /// Clears the toast only when `token` is still the one showing.
    func dismiss(_ token: UUID) {
        guard let toast = current, toast.id == token else { return }
        dismissTask?.cancel()
        current = nil
        toast.onDismiss?()
    }

    /// Clears whatever is showing, regardless of who put it up — a tap on the toast itself.
    func dismissCurrent() {
        dismissTask?.cancel()
        let onDismiss = current?.onDismiss
        current = nil
        onDismiss?()
    }
}

enum SharpitToastTone: Equatable {
    case syncing
    case success
    case error
    case info

    var symbolColor: Color {
        switch self {
        case .syncing, .success, .info: SharpitColor.primary
        case .error: SharpitColor.signalRisk
        }
    }

    var badgeBackground: Color {
        switch self {
        case .syncing: SharpitColor.primary.opacity(0.12)
        case .success, .info: SharpitColor.primary.opacity(0.16)
        case .error: SharpitColor.signalRisk.opacity(0.16)
        }
    }

    var rimColor: Color {
        switch self {
        case .syncing: SharpitColor.primary.opacity(0.2)
        case .success, .info: SharpitColor.primary.opacity(0.4)
        case .error: SharpitColor.signalRisk.opacity(0.45)
        }
    }
}

struct SharpitToastView: View {
    let toast: SharpitToastCenter.Toast

    var body: some View {
        if toast.isDynamicNotification {
            dynamicNotificationBody
        } else {
            compactPillBody
        }
    }

    private var compactPillBody: some View {
        HStack(spacing: SharpitSpacing.xs) {
            ZStack {
                Circle()
                    .fill((toast.accentColor ?? toast.tone.symbolColor).opacity(0.14))
                    .frame(width: 22, height: 22)

                if toast.tone == .syncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: toast.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(toast.accentColor ?? toast.tone.symbolColor)
                }
            }

            Text(toast.message)
                .font(SharpitTypography.system(size: 13, weight: .semibold))
                .foregroundStyle(SharpitColor.cardForeground)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(SharpitColor.card.opacity(0.96))
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(
                    Capsule()
                        .strokeBorder(SharpitColor.border.opacity(0.75), lineWidth: 1)
                )
                .sharpitShadow(.control)
        }
        .accessibilityElement(children: .combine)
    }

    private var dynamicNotificationBody: some View {
        HStack(spacing: 11) {
            // Leading avatar or icon badge matching the app's floating cards
            if let avatarURL = toast.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: toast.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(toast.accentColor ?? toast.tone.symbolColor)
                    case .empty:
                        ProgressView().controlSize(.mini)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill((toast.accentColor ?? toast.tone.symbolColor).opacity(0.14))
                        .frame(width: 32, height: 32)

                    if toast.tone == .syncing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: toast.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(toast.accentColor ?? toast.tone.symbolColor)
                    }
                }
            }

            // Title & message with clear contrast in light and dark mode
            VStack(alignment: .leading, spacing: 2) {
                if let title = toast.title, !title.isEmpty {
                    Text(title)
                        .font(SharpitTypography.system(size: 13, weight: .semibold))
                        .foregroundStyle(SharpitColor.cardForeground)
                        .lineLimit(1)
                }

                if !toast.message.isEmpty {
                    Text(toast.message)
                        .font(SharpitTypography.system(size: 12, weight: .regular))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if toast.action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SharpitColor.card.opacity(0.96))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(SharpitColor.border.opacity(0.75), lineWidth: 1)
                )
                .sharpitShadow(.panel)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hosts the one toast the app shows, pinned under the status bar. `RootView` mounts this
/// above the `TabView`, and again on the Paramètres sheet (sheets cover the tab overlay).
///
/// Swipe up follows the finger and dismisses past ~40 % height or on a fast flick
/// (`SharpitBannerDismiss`); downward drag rubber-bands. Reduce Motion: fade only.
struct SharpitToastHost: View {
    let center: SharpitToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var bannerHeight: CGFloat = 48

    var body: some View {
        VStack(spacing: 0) {
            if let toast = center.current {
                SharpitToastView(toast: toast)
                    .padding(.top, SharpitSpacing.xs)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: BannerHeightKey.self, value: geo.size.height)
                        }
                    )
                    .onPreferenceChange(BannerHeightKey.self) { bannerHeight = max($0, 1) }
                    .offset(y: reduceMotion ? 0 : dragOffset)
                    .opacity(reduceMotion && dragOffset < 0 ? max(0, 1 + dragOffset / max(bannerHeight, 1)) : 1)
                    .gesture(dismissDrag)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -10)),
                                removal: .opacity.combined(with: .offset(y: -10))
                            )
                    )
                    .onTapGesture {
                        if let action = toast.action {
                            action()
                        }
                        center.dismissCurrent()
                    }
                    .onChange(of: toast.id) { _, _ in dragOffset = 0 }
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.94), value: center.current)
        .allowsHitTesting(center.current != nil)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if reduceMotion {
                    // Track upward intent only; dismiss is a fade on end.
                    dragOffset = min(0, value.translation.height)
                    return
                }
                dragOffset = SharpitBannerDismiss.offset(
                    translationY: value.translation.height,
                    height: bannerHeight
                )
            }
            .onEnded { value in
                let shouldClose = SharpitBannerDismiss.shouldDismiss(
                    height: bannerHeight,
                    translationY: value.translation.height,
                    velocityY: value.velocity.height
                )
                if shouldClose {
                    if reduceMotion {
                        withAnimation(SharpitMotion.fade) {
                            center.dismissCurrent()
                            dragOffset = 0
                        }
                    } else {
                        withAnimation(SharpitMotion.reveal) {
                            dragOffset = -bannerHeight * 1.2
                        }
                        center.dismissCurrent()
                        dragOffset = 0
                    }
                } else {
                    withAnimation(SharpitMotion.reveal) {
                        dragOffset = 0
                    }
                }
            }
    }
}

private struct BannerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 48
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
                    String(localized: "Synchronisation…"),
                    symbol: "arrow.triangle.2.circlepath",
                    tone: .syncing,
                    autoDismissAfter: nil
                )
            case .failed:
                token = toastCenter.show(
                    String(localized: "Synchronisation impossible"),
                    symbol: "exclamationmark.triangle.fill",
                    tone: .error,
                    autoDismissAfter: 3.5
                )
            case .idle:
                if oldState == .syncing {
                    token = toastCenter.show(
                        String(localized: "Synchronisé"),
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
