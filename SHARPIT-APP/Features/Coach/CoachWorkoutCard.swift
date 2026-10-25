import SwiftUI

/// A session the coach proposes, drawn from `presentWorkout` (SHARPIT ADR-111): what it is for,
/// how long, its blocks in order the way the watch runs them, and the athlete's own cautions.
/// Nothing on it writes the plan: adding it is asked in the thread and goes through a proposal.
struct CoachWorkoutCard: View {
    let workout: CoachWorkout

    @Environment(\.isExpertReading) private var isExpertReading

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(
                title: workout.type.label,
                symbol: workout.type.symbolName,
                subtitle: CoachWorkoutFormat.summary(workout, isExpertReading: isExpertReading),
                showsChevron: false
            ) {
                if let intensity = workout.intensity {
                    SharpitPill(CoachProposal.intensityLabels[intensity] ?? intensity)
                }
            }

            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text(workout.title)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text(workout.purpose)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .fixedSize(horizontal: false, vertical: true)

            if let blocks = workout.endurancePrescription?.blocks, !blocks.isEmpty {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        CoachWorkoutBlockView(block: block)
                    }
                }
            }

            if let exercises = workout.strengthPrescription?.sets, !exercises.isEmpty {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                        CoachWorkoutLine(
                            title: exercise.exercise,
                            detail: CoachWorkoutFormat.exercise(exercise),
                            notes: exercise.notes
                        )
                    }
                }
            }

            ForEach(Array(workout.warnings.enumerated()), id: \.offset) { _, warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalCaution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

/// One block of a workout: a single step, or a repeated group under its count (« 6× »).
struct CoachWorkoutBlockView: View {
    let block: CoachWorkout.Block

    var body: some View {
        if block.repeats > 1 {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                Text("\(block.repeats)×")
                    .font(SharpitTypography.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityLabel(String(localized: "\(block.repeats) répétitions"))
                steps
                    .padding(.leading, SharpitSpacing.md)
            }
        } else {
            steps
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                CoachWorkoutLine(
                    title: CoachWorkoutFormat.stepKind(step),
                    detail: CoachWorkoutFormat.stepDetail(step),
                    notes: step.notes
                )
            }
        }
    }
}

/// A row of the card: a name, its figures, and the coach's cue under them.
private struct CoachWorkoutLine: View {
    let title: String
    let detail: String
    let notes: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            if !detail.isEmpty {
                Text(detail)
                    .font(SharpitTypography.meta.monospacedDigit())
                    .foregroundStyle(SharpitColor.foreground)
            }
            if let notes, !notes.isEmpty {
                Text(notes)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// The questions the coach offers next. A tap sends one as the athlete's own question.
struct CoachFollowUpsView: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                        Text(suggestion)
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "arrow.up.right")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, SharpitSpacing.md)
                    .padding(.vertical, SharpitSpacing.sm)
                    .frame(minHeight: SharpitSpacing.minimumTouchTarget)
                    .background(SharpitColor.chipSurface, in: Capsule())
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint(String(localized: "Envoie cette question au coach"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
