import SwiftUI

/// « Proposition depuis tes records »: each reference the records revise, the stored value
/// beside the proposed one, kept or left out one by one, then applied — the web's
/// `ThresholdSuggestionCard`.
struct ThresholdSuggestionCard: View {
    let store: ThresholdSuggestionStore
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Proposition depuis tes records")
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)
                Text(ThresholdSuggestionReadout.window(store.preview?.estimates.windowDays))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            VStack(spacing: SharpitSpacing.xs) {
                ForEach(store.offered) { change in
                    ThresholdChangeRow(
                        change: change,
                        isAccepted: store.isAccepted(change.field)
                    ) {
                        SharpitMotion.run(SharpitMotion.selection) { store.toggle(change.field) }
                    }
                }
            }

            HStack(spacing: SharpitSpacing.sm) {
                Button(action: onApply) {
                    Label(
                        ThresholdSuggestionReadout.applyLabel(accepted: store.accepted.count, offered: store.offered.count),
                        systemImage: "checkmark"
                    )
                    .font(SharpitTypography.bodyEmphasis)
                }
                .buttonStyle(.borderedProminent)
                .tint(SharpitColor.primary)
                .disabled(store.accepted.isEmpty)

                if store.accepted.isEmpty {
                    Text("Aucune proposition retenue.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

/// One proposal: what moves, which way, from what to what, and whether it is kept.
private struct ThresholdChangeRow: View {
    let change: V1ThresholdChange
    let isAccepted: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(change.label)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Text(ThresholdSuggestionReadout.directionLabel(change.direction))
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(SharpitColor.analysisGrid.opacity(0.45), in: Capsule())
                }
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                    Text(change.from)
                        .font(SharpitTypography.instrument)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .accessibilityHidden(true)
                    Text(change.to)
                        .font(SharpitTypography.instrument.weight(.semibold))
                        .foregroundStyle(SharpitColor.foreground)
                }
                .monospacedDigit()
            }
            Spacer(minLength: SharpitSpacing.xs)
            SharpitKeepToggle(isSelected: isAccepted, action: onToggle)
        }
        .padding(.horizontal, SharpitSpacing.sm)
        .padding(.vertical, SharpitSpacing.xs)
        .background(SharpitColor.analysisGrid.opacity(0.18), in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
        .opacity(isAccepted ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.label), \(change.from) vers \(change.to)")
    }
}

/// The card's words, kept apart so they are tested.
nonisolated enum ThresholdSuggestionReadout {
    /// « Capacité démontrée sur 120 jours — pas le record de toujours. »
    static func window(_ days: Int?) -> String {
        guard let days, days > 0 else { return "Capacité démontrée récemment — pas le record de toujours." }
        return "Capacité démontrée sur \(days) jours — pas le record de toujours."
    }

    /// « Appliquer », or « Appliquer (2) » when some proposals were left out.
    static func applyLabel(accepted: Int, offered: Int) -> String {
        accepted > 0 && accepted < offered ? "Appliquer (\(accepted))" : "Appliquer"
    }

    static func directionLabel(_ direction: V1ThresholdDirection) -> String {
        switch direction {
        case .up: "Hausse"
        case .down: "Baisse"
        case .set: "Nouveau"
        }
    }
}
