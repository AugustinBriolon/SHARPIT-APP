import SwiftUI

/// The session's breakdown — what to actually do, in order.
///
/// A rail of connected marks rather than a bulleted list: the steps happen one after the
/// other, and the shape should say so before the words do. Targets are already resolved
/// server-side, so nothing here computes a band.
struct PlannedSessionBreakdownList: View {
    let steps: [V1PlannedSessionStep]
    let derived: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(spacing: SharpitSpacing.xs) {
                SharpitEyebrow("Déroulé")
                Spacer(minLength: 0)
                if derived {
                    PlannedStepsEstimatedTag()
                }
            }
            PlannedStepRail(steps: steps)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

/// The athlete did not write this breakdown; saying so is the honest version of showing it.
struct PlannedStepsEstimatedTag: View {
    var body: some View {
        Text("Estimé")
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(SharpitColor.mutedForeground)
            .padding(.horizontal, SharpitSpacing.xs)
            .padding(.vertical, 2)
            .background(SharpitColor.analysisSurfaceAlt, in: Capsule())
    }
}

/// The steps on their rail, without a panel — the breakdown's own body, and a brick leg's.
///
/// A repeated set is one mark on the rail, its steps held together in a well under the
/// count: the block and its recovery are done five times, as a pair.
struct PlannedStepRail: View {
    let steps: [V1PlannedSessionStep]

    private var sets: [PlannedStepSet] { PlannedStepSet.sets(from: steps) }

    var body: some View {
        let sets = sets
        VStack(spacing: 0) {
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                RailRow(isFirst: index == 0, isLast: index == sets.count - 1, isRepeat: set.isRepeated) {
                    if set.isRepeated {
                        RepeatedSet(set: set)
                    } else {
                        ForEach(set.steps) { PlannedStepContent(step: $0) }
                    }
                }
            }
        }
    }
}

/// A mark on a line. The line stops at the first and last marks so the rail reads as a
/// sequence with a beginning and an end, not as a fragment of something longer.
private struct RailRow<Content: View>: View {
    let isFirst: Bool
    let isLast: Bool
    let isRepeat: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : SharpitColor.analysisBorder)
                    .frame(width: 1, height: isRepeat ? 3 : 6)
                mark
                Rectangle()
                    .fill(isLast ? Color.clear : SharpitColor.analysisBorder)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 13)
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, isLast ? 0 : SharpitSpacing.md)
        }
    }

    @ViewBuilder
    private var mark: some View {
        if isRepeat {
            Image(systemName: "repeat")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(SharpitColor.primaryForeground)
                .frame(width: 13, height: 13)
                .background(SharpitColor.primary, in: Circle())
        } else {
            Circle()
                .fill(SharpitColor.primary)
                .frame(width: 7, height: 7)
        }
    }
}

/// « 5 × » over the steps it repeats, held in one well so they read as a pair.
private struct RepeatedSet: View {
    let set: PlannedStepSet

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text("\(set.repeatCount)")
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.primary)
                Text("fois")
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                ForEach(set.steps) { PlannedStepContent(step: $0) }
            }
            .padding(SharpitSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                SharpitColor.analysisSurfaceAlt,
                in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(set.repeatCount) fois : " + set.steps.map(\.spokenLabel).joined(separator: ", puis "))
    }
}

/// One step's words: what, how long, at what, and the note beside it.
///
/// Strength labels are often long French movement names; they must wrap beside the
/// detail rather than widen the drawer past the screen (horizontal scroll).
private struct PlannedStepContent: View {
    let step: V1PlannedSessionStep

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text(step.label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail = step.detail {
                    Text(detail)
                        .font(SharpitTypography.instrument)
                        .foregroundStyle(SharpitColor.foreground)
                        .layoutPriority(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            if let target = step.target {
                Text(target)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notes = step.notes, !notes.isEmpty {
                Text(notes)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.spokenLabel)
    }
}

private extension V1PlannedSessionStep {
    var spokenLabel: String {
        [label, detail, target, notes].compactMap { $0 }.joined(separator: ", ")
    }
}

#Preview("Endurance") {
    PlannedSessionBreakdownList(
        steps: [
            V1PlannedSessionStep(key: "0-0", label: "Échauffement", detail: "15 min", group: "0"),
            V1PlannedSessionStep(
                key: "1-0",
                label: "Bloc",
                detail: "3 min",
                target: "4:05 – 4:20 /km",
                group: "1",
                repeatCount: 5
            ),
            V1PlannedSessionStep(key: "1-1", label: "Récup", detail: "90 s", group: "1", repeatCount: 5),
            V1PlannedSessionStep(key: "2-0", label: "Retour au calme", detail: "10 min", group: "2"),
        ],
        derived: false
    )
    .padding()
    .background(SharpitCanvasBackground())
}

#Preview("Force / mobilité") {
    PlannedSessionBreakdownList(
        steps: [
            V1PlannedSessionStep(
                key: "strength-0",
                label: "Étirements dynamiques hanches et ischio-jambiers unilatéraux",
                detail: "3 × 45 s"
            ),
            V1PlannedSessionStep(
                key: "strength-1",
                label: "Rotation externe d'épaule à la bande élastique",
                detail: "3 × 12",
                target: "Bande légère"
            ),
        ],
        derived: false
    )
    .frame(width: 375)
    .padding()
    .background(SharpitCanvasBackground())
}
