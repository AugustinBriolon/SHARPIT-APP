import Observation
import SwiftUI

/// The guided strength session running in the app, one at a time (`docs/adr/0030`). It lives
/// above the tabs, not in the screen that started it, so « Réduire » only slides it away: the
/// sets, the rest and the clock keep going while the athlete looks elsewhere, and the bar
/// above the tabs brings it back.
@Observable
@MainActor
final class GuidedWorkoutDock {
    struct Active: Identifiable {
        let id = UUID()
        let session: GuidedStrengthSession
        let finish: GuidedStrengthFinishContext
    }

    private(set) var active: Active?
    private(set) var isMinimized = false

    /// Starts a session, or brings back the one already running: two at once would split the sets.
    func start(_ session: GuidedStrengthSession, finish: GuidedStrengthFinishContext) {
        if active == nil { active = Active(session: session, finish: finish) }
        isMinimized = false
    }

    func minimize() {
        guard active != nil else { return }
        isMinimized = true
    }

    func expand() { isMinimized = false }

    /// Saved or quit: the session is gone.
    func end() {
        active = nil
        isMinimized = false
    }
}

/// Mounts the running session over the app and its bar above the tabs.
struct GuidedWorkoutDockHost: ViewModifier {
    let dock: GuidedWorkoutDock

    func body(content: Content) -> some View {
        accessory(content)
            .overlay {
                if let active = dock.active {
                    GeometryReader { proxy in
                        GuidedStrengthWorkoutView(session: active.session, finish: active.finish)
                            .id(active.id)
                            .background(SharpitCanvasBackground().ignoresSafeArea())
                            .offset(y: dock.isMinimized ? proxy.size.height + proxy.safeAreaInsets.bottom + 40 : 0)
                            .allowsHitTesting(!dock.isMinimized)
                            .accessibilityHidden(dock.isMinimized)
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(SharpitMotion.reveal, value: dock.isMinimized)
            .animation(SharpitMotion.reveal, value: dock.active?.id)
            .environment(dock)
    }

    /// The system's bar above the tabs (iOS 26.1), else a glass capsule floating over them.
    @ViewBuilder
    private func accessory(_ content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: dock.isMinimized) { bar }
        } else {
            content.overlay(alignment: .bottom) {
                if dock.isMinimized {
                    bar
                        .frame(minHeight: SharpitSpacing.rowHeight)
                        .sharpitGlassCapsule()
                        .padding(.horizontal, SharpitSpacing.pageInset)
                        // shortcut: clears the iPhone tab bar by a fixed height; revisit if the bar's height changes.
                        .padding(.bottom, 64)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder private var bar: some View {
        if let active = dock.active {
            GuidedWorkoutAccessory(session: active.session) { dock.expand() }
        }
    }
}

/// « Renfo · 12:34 » above the tabs while a session runs out of sight; a tap brings it back.
struct GuidedWorkoutAccessory: View {
    let session: GuidedStrengthSession
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "dumbbell")
                    .foregroundStyle(SharpitColor.foreground)
                Text(session.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                Spacer(minLength: SharpitSpacing.xs)
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text(PlannedSessionFormat.elapsedClock(Int(context.date.timeIntervalSince(session.startedAt))))
                        .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.up")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .padding(.horizontal, SharpitSpacing.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Séance en cours : \(session.title)"))
        .accessibilityHint("Rouvre la séance")
    }
}
