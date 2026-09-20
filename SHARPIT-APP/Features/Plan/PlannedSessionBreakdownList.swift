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
                    // The athlete did not write this; saying so is the honest version of
                    // showing it at all.
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

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    PlannedSessionStepRow(
                        step: step,
                        isFirst: index == 0,
                        isLast: index == steps.count - 1
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

private struct PlannedSessionStepRow: View {
    let step: V1PlannedSessionStep
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            rail
            content
                .padding(.bottom, isLast ? 0 : SharpitSpacing.md)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// A mark on a line. The line stops at the first and last marks so the rail reads as a
    /// sequence with a beginning and an end, not as a fragment of something longer.
    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : SharpitColor.analysisBorder)
                .frame(width: 1, height: 6)
            Circle()
                .fill(SharpitColor.primary)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(isLast ? Color.clear : SharpitColor.analysisBorder)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 7)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            HStack(spacing: SharpitSpacing.xs) {
                if step.repeatCount > 1 {
                    Text("\(step.repeatCount)×")
                        .font(SharpitTypography.instrument)
                        .foregroundStyle(SharpitColor.primary)
                }
                Text(step.label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 0)
                if let detail = step.detail {
                    Text(detail)
                        .font(SharpitTypography.instrument)
                        .foregroundStyle(SharpitColor.foreground)
                }
            }

            if let target = step.target {
                Text(target)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.primary)
            }

            if let notes = step.notes, !notes.isEmpty {
                Text(notes)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessibilityLabel: String {
        [
            step.repeatCount > 1 ? "\(step.repeatCount) fois" : nil,
            step.label,
            step.detail,
            step.target,
            step.notes,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

#Preview {
    PlannedSessionBreakdownList(
        steps: [
            V1PlannedSessionStep(key: "0", label: "Échauffement", detail: "15 min"),
            V1PlannedSessionStep(
                key: "1",
                label: "Bloc",
                detail: "3 min",
                target: "4:05 – 4:20 /km",
                repeatCount: 5
            ),
            V1PlannedSessionStep(key: "2", label: "Récup", detail: "90 s", repeatCount: 5),
            V1PlannedSessionStep(key: "3", label: "Retour au calme", detail: "10 min"),
        ],
        derived: false
    )
    .padding()
    .background(SharpitCanvasBackground())
}
