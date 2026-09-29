import AppIntents
import SwiftUI
import WidgetKit

/// « Demander au coach »: the way into Coach from the home screen, drawn as its composer — the
/// field the athlete lands on. It holds no data: nothing on it can be stale.
struct CoachWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AskCoach", provider: SnapshotProvider()) { _ in
            CoachWidgetView()
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(WidgetSnapshot.link("/coach"))
        }
        .configurationDisplayName("Demander au coach")
        .description("Ouvre le coach, prêt pour ta question.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct CoachWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 18, weight: .semibold))
                    .widgetAccentable()
            }
            .accessibilityLabel("Demander au coach")
        default:
            WidgetFrame("Coach", symbol: "bubble.left.and.text.bubble.right", tint: SharpitColor.primary) {
                WidgetTitle(text: "Demander au coach")
                    .padding(.bottom, 10)
                HStack(spacing: 6) {
                    Text("Ta question…")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Spacer(minLength: 0)
                    SendMark()
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .background(SharpitColor.foreground.opacity(0.07), in: Capsule())
            }
        }
    }
}

/// The composer's send button. In full color, a Forest disc with the arrow knocked out; in a
/// tinted or clear home screen the system paints every shape one color, so the arrow is cut
/// out of the disc instead of drawn over it — else it vanished into it.
private struct SendMark: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SharpitColor.primaryForeground)
                .frame(width: 22, height: 22)
                .background(SharpitColor.primary, in: Circle())
        } else {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.monochrome)
                .widgetAccentable()
        }
    }
}

/// The same way in, from Control Center, the lock screen or the Action button.
struct CoachControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.sharpit.ios.ask-coach") {
            ControlWidgetButton(action: OpenURLIntent(WidgetSnapshot.link("/coach"))) {
                Label("Demander au coach", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .displayName("Demander au coach")
        .description("Ouvre le coach de SharpIt.")
    }
}
