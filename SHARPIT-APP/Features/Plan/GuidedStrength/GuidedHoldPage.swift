import AudioToolbox
import SwiftUI
import UIKit

/// A timed hold as the athlete does it, phone on the floor (SHARPIT ADR-121, `docs/adr/0030`):
/// a few seconds to get in place, the hold, and for a move done on each side a few seconds to
/// switch before the second side. Pure: the step is read from the time elapsed.
nonisolated struct GuidedHoldClock: Equatable, Sendable {
    /// A hold with no length written: the server's own default (DEFAULT_MOBILITY_HOLD_SEC).
    static let fallbackSec = 30
    /// Getting into position, and changing legs: measured at 4–6 s, given 5.
    static let prepareSec = 5
    static let switchSec = 5

    let durationSec: Int
    let perSide: Bool

    enum Step: Equatable, Sendable {
        case prepare
        /// `side` is 0 for the first side, 1 for the second; nil when the hold has no sides.
        case hold(side: Int?)
        case switchSides
    }

    struct Segment: Equatable, Sendable {
        let step: Step
        let seconds: Int
    }

    enum Phase: Equatable {
        case running(Step, remaining: Int)
        case finished
    }

    /// Everything the hold will do, in order: shown before it starts, so nothing comes as a surprise.
    var segments: [Segment] {
        let hold = max(durationSec, 1)
        guard perSide else {
            return [Segment(step: .prepare, seconds: Self.prepareSec), Segment(step: .hold(side: nil), seconds: hold)]
        }
        return [
            Segment(step: .prepare, seconds: Self.prepareSec),
            Segment(step: .hold(side: 0), seconds: hold),
            Segment(step: .switchSides, seconds: Self.switchSec),
            Segment(step: .hold(side: 1), seconds: hold),
        ]
    }

    var totalSec: Int { segments.reduce(0) { $0 + $1.seconds } }

    func phase(elapsed: TimeInterval) -> Phase {
        var left = max(Int(elapsed.rounded(.down)), 0)
        for segment in segments {
            if left < segment.seconds { return .running(segment.step, remaining: segment.seconds - left) }
            left -= segment.seconds
        }
        return .finished
    }

    /// Where the button jumps to from this step: the start of the next hold (the count-in, the
    /// first side and the switch all lead to a side), or nil on the last hold, which ends the set.
    func skipTarget(from phase: Phase) -> TimeInterval? {
        guard case .running(let step, _) = phase,
              let index = segments.firstIndex(where: { $0.step == step }) else { return nil }
        var start = 0
        for (offset, segment) in segments.enumerated() {
            if offset > index, case .hold = segment.step { return TimeInterval(start) }
            start += segment.seconds
        }
        return nil
    }

    /// The hold segments only — what the sequence strip lists.
    var holds: [Segment] { segments.filter { if case .hold = $0.step { true } else { false } } }
}

/// The hold's countdown, pushed over the exercise. It says the whole sequence before it starts
/// (« Gauche 30 s · Droite 30 s »), counts the athlete in, announces the switch with its own
/// countdown and a sound, ticks the last three seconds of each step, keeps the screen awake and
/// tells VoiceOver each step. The set is ticked at the end, or earlier with « Terminer ».
struct GuidedHoldPage: View {
    let exerciseName: String
    let clock: GuidedHoldClock
    let onFinished: () -> Void

    @State private var startedAt = Date()
    @State private var hasFinished = false

    var body: some View {
        VStack(spacing: SharpitSpacing.lg) {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                TimelineView(.periodic(from: startedAt, by: 0.25)) { context in
                    let phase = clock.phase(elapsed: context.date.timeIntervalSince(startedAt))
                    VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                        content(phase)
                        actionButton(phase)
                    }
                    .onChange(of: phase) { old, new in cue(from: old, to: new) }
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
            Spacer(minLength: 0)
        }
        .padding(SharpitSpacing.pageInset)
        // The phone lies on the floor through a hold: it must not lock mid-countdown.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func content(_ phase: GuidedHoldClock.Phase) -> some View {
        let step: GuidedHoldClock.Step? = if case .running(let step, _) = phase { step } else { nil }
        let remaining = if case .running(_, let left) = phase { left } else { 0 }
        let length = clock.segments.first { $0.step == step }?.seconds ?? 1
        return VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(phase))
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text(Self.next(phase, clock: clock) ?? exerciseName)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            if clock.perSide { sequence(current: step) }
            ZStack {
                SharpitScoreRing(fraction: Double(remaining) / Double(length), lineWidth: 18)
                Text(PlannedSessionFormat.restClock(remaining))
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(step == .hold(side: 0) || step == .hold(side: 1) || step == .hold(side: nil)
                        ? SharpitColor.foreground : SharpitColor.mutedForeground)
                    .contentTransition(.numericText())
            }
            .frame(width: 220, height: 220)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    /// Forward one step at a time: into the first side, on to the other side, then the set is done.
    private func actionButton(_ phase: GuidedHoldClock.Phase) -> some View {
        let target = clock.skipTarget(from: phase)
        return SharpitPrimaryButton(
            title: Self.actionTitle(phase, clock: clock),
            trailingSymbol: target == nil ? "checkmark.circle.fill" : "forward.circle.fill"
        ) {
            guard let target else { return finish() }
            startedAt = Date().addingTimeInterval(-target)
        }
    }

    static func actionTitle(_ phase: GuidedHoldClock.Phase, clock: GuidedHoldClock) -> String {
        guard clock.skipTarget(from: phase) != nil else { return String(localized: "Terminer la série") }
        switch phase {
        case .running(.hold(side: 0), _): return String(localized: "Passer au côté droit")
        case .running(.switchSides, _): return String(localized: "Commencer le côté droit")
        default: return String(localized: "Commencer")
        }
    }

    /// « Gauche 30 s · Droite 30 s », the side under way in ink, a side done ticked.
    private func sequence(current: GuidedHoldClock.Step?) -> some View {
        let order: [GuidedHoldClock.Step?] = clock.segments.map(\.step)
        let position = current.flatMap { step in order.firstIndex { $0 == step } } ?? order.count
        return HStack(spacing: SharpitSpacing.md) {
            ForEach(Array(clock.holds.enumerated()), id: \.offset) { index, segment in
                let at = order.firstIndex { $0 == segment.step } ?? 0
                let isDone = at < position
                let isNow = at == position
                HStack(spacing: SharpitSpacing.xxs) {
                    if isDone { Image(systemName: "checkmark") }
                    Text(Self.sideName(index) + " · " + PlannedSessionFormat.durationSeconds(segment.seconds))
                }
                .font(SharpitTypography.system(size: 15, weight: isNow ? .semibold : .regular, relativeTo: .subheadline, digits: true))
                .foregroundStyle(isNow ? SharpitColor.foreground : SharpitColor.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func sideName(_ index: Int) -> String {
        index == 0 ? String(localized: "Gauche") : String(localized: "Droite")
    }

    static func title(_ phase: GuidedHoldClock.Phase) -> String {
        switch phase {
        case .running(.prepare, _): String(localized: "Mets-toi en place")
        case .running(.hold(side: 0), _): String(localized: "Côté gauche")
        case .running(.hold(side: 1), _): String(localized: "Côté droit")
        case .running(.hold, _): String(localized: "Maintien")
        case .running(.switchSides, _): String(localized: "Change de côté")
        case .finished: String(localized: "Terminé")
        }
    }

    /// What comes next, so the second side is never a surprise; nil on the last hold.
    static func next(_ phase: GuidedHoldClock.Phase, clock: GuidedHoldClock) -> String? {
        guard case .running(let step, _) = phase,
              let index = clock.segments.firstIndex(where: { $0.step == step }),
              let following = clock.segments.dropFirst(index + 1).first(where: { if case .hold = $0.step { true } else { false } })
        else { return nil }
        let length = PlannedSessionFormat.durationSeconds(following.seconds)
        switch following.step {
        case .hold(side: 0): return String(localized: "Ensuite : côté gauche, \(length)")
        case .hold(side: 1): return String(localized: "Ensuite : côté droit, \(length)")
        default: return String(localized: "Ensuite : maintien, \(length)")
        }
    }

    /// A sound on each new step and on the last three seconds of each (no haptic: the phone
    /// is on the floor, and the app keeps haptics for a notch under the finger); VoiceOver hears
    /// the step's name.
    private func cue(from old: GuidedHoldClock.Phase, to new: GuidedHoldClock.Phase) {
        if new == .finished { return finish() }
        guard case .running(let step, let remaining) = new else { return }
        if case .running(let before, _) = old, before != step {
            AudioServicesPlaySystemSound(1057)
            AccessibilityNotification.Announcement(Self.title(new)).post()
        } else if (1...3).contains(remaining), old != new {
            AudioServicesPlaySystemSound(1103)
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished()
    }
}
