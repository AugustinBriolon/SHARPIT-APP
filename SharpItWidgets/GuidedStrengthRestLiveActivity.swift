import ActivityKit
import SwiftUI
import WidgetKit

/// Lock screen + Dynamic Island for a guided strength session, laid out as Apple's Timer:
/// the clock is the hero, a lime bar drains with the rest, and « Ensuite » names the next set.
/// In a set the clock counts the session up instead, and the bar steps aside.
struct GuidedStrengthRestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuidedStrengthRestAttributes.self) { context in
            GuidedStrengthSessionLockScreen(
                state: context.state,
                title: context.attributes.sessionTitle,
                startedAt: context.attributes.startedAt
            )
            .activityBackgroundTint(LiveActivityStyle.ground)
            .activitySystemActionForegroundColor(LiveActivityStyle.accent)
            .widgetURL(WidgetSnapshot.link("/plan"))
        } dynamicIsland: { context in
            let state = context.state
            let startedAt = context.attributes.startedAt
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityTile(symbol: GuidedStrengthLiveReadout.symbol(state.kind), size: 36)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GuidedStrengthClock(state: state, startedAt: startedAt)
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundStyle(state.kind == .resting ? LiveActivityStyle.accent : .white)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 96, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        LiveActivityEyebrow(text: GuidedStrengthRestLiveActivityCopy.eyebrow(kind: state.kind))
                        Text(GuidedStrengthLiveReadout.headline(title: context.attributes.sessionTitle, kind: state.kind))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        GuidedStrengthRestBar(state: state)
                        if let next = GuidedStrengthLiveReadout.next(state) {
                            GuidedStrengthNextLine(next: next, ink: .white)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: GuidedStrengthLiveReadout.symbol(state.kind))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiveActivityStyle.accent)
            } compactTrailing: {
                GuidedStrengthClock(state: state, startedAt: startedAt)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(state.kind == .resting ? LiveActivityStyle.accent : .white)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44, alignment: .trailing)
            } minimal: {
                GuidedStrengthMinimal(state: state)
            }
            .keylineTint(LiveActivityStyle.accent)
            .widgetURL(WidgetSnapshot.link("/plan"))
        }
    }
}

/// Words and glyphs shared by the lock screen and the Island.
private enum GuidedStrengthLiveReadout {
    static func symbol(_ kind: GuidedStrengthRestAttributes.Kind) -> String {
        kind == .resting ? "timer" : "dumbbell.fill"
    }

    static func headline(title: String, kind: GuidedStrengthRestAttributes.Kind) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? GuidedStrengthRestLiveActivityCopy.eyebrow(kind: kind) : trimmed
    }

    /// « Développé couché · 4 × 8 · 60 kg », or nil when nothing is known of the next set.
    static func next(_ state: GuidedStrengthRestAttributes.ContentState) -> String? {
        let line = GuidedStrengthRestLiveActivityCopy.subtitle(
            nextExercise: state.nextExercise,
            nextSetLine: state.nextSetLine
        )
        return line == "Séance en cours" || line.isEmpty ? nil : line
    }

    /// The rest's span when it is running and its start is known.
    static func restInterval(_ state: GuidedStrengthRestAttributes.ContentState) -> ClosedRange<Date>? {
        guard state.kind == .resting, !state.isPaused,
              let start = state.restStartedAt, let end = state.endsAt, start < end else { return nil }
        return start...end
    }
}

/// The hero figure: the rest counting down (or frozen when paused), else the session counting up.
private struct GuidedStrengthClock: View {
    let state: GuidedStrengthRestAttributes.ContentState
    let startedAt: Date

    var body: some View {
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

/// A lime bar that drains with the rest; absent in a set or while paused.
private struct GuidedStrengthRestBar: View {
    let state: GuidedStrengthRestAttributes.ContentState

    var body: some View {
        if let interval = GuidedStrengthLiveReadout.restInterval(state) {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(LiveActivityStyle.accent)
        }
    }
}

/// « Ensuite » then the next set, muted label and white words.
private struct GuidedStrengthNextLine: View {
    let next: String
    let ink: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("Ensuite")
                .foregroundStyle(ink.opacity(0.55))
            Text(next)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .font(.system(size: 15, weight: .medium))
    }
}

/// The Island's smallest form: a lime ring draining with the rest, else the glyph.
private struct GuidedStrengthMinimal: View {
    let state: GuidedStrengthRestAttributes.ContentState

    var body: some View {
        if let interval = GuidedStrengthLiveReadout.restInterval(state) {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LiveActivityStyle.accent)
            }
            .progressViewStyle(.circular)
            .tint(LiveActivityStyle.accent)
        } else {
            Image(systemName: GuidedStrengthLiveReadout.symbol(state.kind))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LiveActivityStyle.accent)
        }
    }
}

private struct GuidedStrengthSessionLockScreen: View {
    let state: GuidedStrengthRestAttributes.ContentState
    let title: String
    let startedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                LiveActivityTile(symbol: GuidedStrengthLiveReadout.symbol(state.kind))
                VStack(alignment: .leading, spacing: 2) {
                    LiveActivityEyebrow(text: state.isPaused
                        ? "Repos en pause"
                        : GuidedStrengthRestLiveActivityCopy.eyebrow(kind: state.kind))
                    Text(GuidedStrengthLiveReadout.headline(title: title, kind: state.kind))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LiveActivityStyle.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                GuidedStrengthClock(state: state, startedAt: startedAt)
                    .font(.system(size: 36, weight: .bold).monospacedDigit())
                    .foregroundStyle(LiveActivityStyle.ink)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)
                    .layoutPriority(1)
            }
            GuidedStrengthRestBar(state: state)
            if let next = GuidedStrengthLiveReadout.next(state) {
                GuidedStrengthNextLine(next: next, ink: LiveActivityStyle.ink)
            }
        }
        .padding(LiveActivityStyle.margin)
    }
}
