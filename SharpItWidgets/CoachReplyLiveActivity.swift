import ActivityKit
import SwiftUI
import WidgetKit

/// Lock screen + Dynamic Island for a coach turn left mid-reply.
struct CoachReplyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoachReplyAttributes.self) { context in
            CoachReplyLockScreen(state: context.state)
                .widgetURL(WidgetSnapshot.link("/coach"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(CoachReplyLiveActivityCopy.title)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(CoachReplyLiveActivityCopy.subtitle(
                        phase: context.state.phase,
                        preview: context.state.preview
                    ))
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                }
            } compactLeading: {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            } compactTrailing: {
                Text(compactTrailing(context.state.phase))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
            } minimal: {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            }
            .widgetURL(WidgetSnapshot.link("/coach"))
        }
    }

    private func compactTrailing(_ phase: CoachReplyAttributes.Phase) -> String {
        switch phase {
        case .replying: "…"
        case .ready: "OK"
        case .failed: "!"
        }
    }
}

private struct CoachReplyLockScreen: View {
    let state: CoachReplyAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(CoachReplyLiveActivityCopy.title)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Text(CoachReplyLiveActivityCopy.subtitle(phase: state.phase, preview: state.preview))
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(SharpitColor.background.opacity(0.92))
    }
}
