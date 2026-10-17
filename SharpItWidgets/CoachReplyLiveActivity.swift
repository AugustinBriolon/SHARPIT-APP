import ActivityKit
import SwiftUI
import WidgetKit

/// Lock screen + Dynamic Island for a coach turn left mid-reply: the lime tile, « Coach », what
/// is happening, then the reply's first line once it is there. A spinner while it writes, a
/// lime check once it is ready — the state reads at a glance, as Apple's own activities do.
struct CoachReplyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoachReplyAttributes.self) { context in
            CoachReplyLockScreen(state: context.state)
                .activityBackgroundTint(LiveActivityStyle.ground)
                .activitySystemActionForegroundColor(LiveActivityStyle.accent)
                .widgetURL(WidgetSnapshot.link("/coach"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityTile(symbol: "text.bubble.fill", size: 36)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CoachReplyStatusMark(phase: context.state.phase)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        LiveActivityEyebrow(text: CoachReplyLiveActivityCopy.title)
                        Text(CoachReplyLiveActivityCopy.headline(phase: context.state.phase))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let detail = CoachReplyLiveActivityCopy.detail(
                        phase: context.state.phase,
                        preview: context.state.preview
                    ) {
                        Text(detail)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                            .privacySensitive()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiveActivityStyle.accent)
            } compactTrailing: {
                CoachReplyStatusMark(phase: context.state.phase, size: 14)
            } minimal: {
                CoachReplyStatusMark(phase: context.state.phase, size: 14)
            }
            .keylineTint(LiveActivityStyle.accent)
            .widgetURL(WidgetSnapshot.link("/coach"))
        }
    }
}

/// Writing, ready or stopped — a spinner, a lime check, a caution mark.
private struct CoachReplyStatusMark: View {
    let phase: CoachReplyAttributes.Phase
    var size: CGFloat = 22

    var body: some View {
        switch phase {
        case .replying:
            ProgressView()
                .tint(.white)
                .controlSize(size < 20 ? .mini : .regular)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(LiveActivityStyle.accent)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(SharpitColor.signalCaution)
        }
    }
}

private struct CoachReplyLockScreen: View {
    let state: CoachReplyAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LiveActivityTile(symbol: "text.bubble.fill")
            VStack(alignment: .leading, spacing: 2) {
                LiveActivityEyebrow(text: CoachReplyLiveActivityCopy.title)
                Text(CoachReplyLiveActivityCopy.headline(phase: state.phase))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LiveActivityStyle.ink)
                    .lineLimit(1)
                if let detail = CoachReplyLiveActivityCopy.detail(phase: state.phase, preview: state.preview) {
                    Text(detail)
                        .font(.system(size: 15))
                        .foregroundStyle(LiveActivityStyle.ink.opacity(0.7))
                        .lineLimit(2)
                        // The reply quotes the athlete's health context: hidden on a locked screen.
                        .privacySensitive()
                }
            }
            Spacer(minLength: 8)
            CoachReplyStatusMark(phase: state.phase)
        }
        .padding(LiveActivityStyle.margin)
    }
}
