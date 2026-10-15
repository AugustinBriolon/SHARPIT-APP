import ActivityKit
import SwiftUI
import WidgetKit

/// Lock screen + Dynamic Island for a guided strength session (sets + rest).
///
/// Content is sparse (glyph + clock ± next set): keep one dense row on the lock screen and
/// avoid inflated Island regions that stretch empty chrome.
struct GuidedStrengthRestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuidedStrengthRestAttributes.self) { context in
            GuidedStrengthSessionLockScreen(
                state: context.state,
                title: context.attributes.sessionTitle,
                startedAt: context.attributes.startedAt
            )
            .widgetURL(WidgetSnapshot.link("/plan"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: islandSymbol(context.state.kind))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SharpitColor.primary)
                        Text(islandLeadingLabel(context))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SharpitColor.foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    sessionClock(state: context.state, startedAt: context.attributes.startedAt)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(SharpitColor.foreground)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let detail = islandBottomDetail(context.state) {
                        Text(detail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: islandSymbol(context.state.kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            } compactTrailing: {
                sessionClock(state: context.state, startedAt: context.attributes.startedAt)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(minWidth: 36, alignment: .trailing)
            } minimal: {
                Image(systemName: islandSymbol(context.state.kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            }
            .widgetURL(WidgetSnapshot.link("/plan"))
        }
    }

    private func islandSymbol(_ kind: GuidedStrengthRestAttributes.Kind) -> String {
        kind == .resting ? "timer" : "dumbbell.fill"
    }

    /// Compact leading: next move if known, else session title / phase.
    private func islandLeadingLabel(
        _ context: ActivityViewContext<GuidedStrengthRestAttributes>
    ) -> String {
        let exercise = context.state.nextExercise.trimmingCharacters(in: .whitespacesAndNewlines)
        if !exercise.isEmpty { return exercise }
        let title = context.attributes.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return GuidedStrengthRestLiveActivityCopy.eyebrow(kind: context.state.kind)
    }

    /// Bottom only when it adds something the leading line does not already say.
    private func islandBottomDetail(_ state: GuidedStrengthRestAttributes.ContentState) -> String? {
        let exercise = state.nextExercise.trimmingCharacters(in: .whitespacesAndNewlines)
        let setLine = state.nextSetLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !exercise.isEmpty, !setLine.isEmpty { return setLine }
        if exercise.isEmpty, !setLine.isEmpty { return setLine }
        return nil
    }

    @ViewBuilder
    private func sessionClock(
        state: GuidedStrengthRestAttributes.ContentState,
        startedAt: Date
    ) -> some View {
        if state.kind == .resting {
            if state.isPaused {
                Text(GuidedStrengthRestLiveActivityCopy.pausedLabel(seconds: state.remainingWhenPaused))
            } else if let endsAt = state.endsAt, endsAt > .now {
                Text(timerInterval: Date.now...endsAt, countsDown: true, showsHours: false)
            } else {
                Text("0:00")
            }
        } else {
            Text(startedAt, style: .timer)
        }
    }
}

/// One dense lock-screen row: glyph · title/set · clock. No two-line sprawl, no giant timer.
private struct GuidedStrengthSessionLockScreen: View {
    let state: GuidedStrengthRestAttributes.ContentState
    let title: String
    let startedAt: Date

    private var headline: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return GuidedStrengthRestLiveActivityCopy.eyebrow(kind: state.kind)
    }

    private var detail: String? {
        let subtitle = GuidedStrengthRestLiveActivityCopy.subtitle(
            nextExercise: state.nextExercise,
            nextSetLine: state.nextSetLine
        )
        // Don't repeat a generic "Séance en cours" under an already clear session title.
        if subtitle == "Séance en cours" { return nil }
        if subtitle == headline { return nil }
        return subtitle.isEmpty ? nil : subtitle
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: state.kind == .resting ? "timer" : "dumbbell.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            clock
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(SharpitColor.foreground)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .activityBackgroundTint(SharpitColor.background.opacity(0.92))
    }

    @ViewBuilder
    private var clock: some View {
        if state.kind == .resting {
            if state.isPaused {
                Text(GuidedStrengthRestLiveActivityCopy.pausedLabel(seconds: state.remainingWhenPaused))
            } else if let endsAt = state.endsAt, endsAt > .now {
                Text(timerInterval: Date.now...endsAt, countsDown: true, showsHours: false)
            } else {
                Text("0:00")
            }
        } else {
            Text(startedAt, style: .timer)
        }
    }
}
