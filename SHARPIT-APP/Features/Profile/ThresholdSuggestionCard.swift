import SwiftUI

/// « Proposition depuis tes records »: each reference the records revise, the stored value
/// beside the proposed one, kept or left out one by one, then applied — the web's
/// `ThresholdSuggestionCard`.
struct ThresholdSuggestionCard: View {
    let store: ThresholdSuggestionStore
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("D'après tes records")
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer(minLength: SharpitSpacing.xs)
                    CliniqueStatusPill(String(localized: "\(store.offered.count) à revoir"), status: .watch)
                }
                Text(ThresholdSuggestionReadout.window(store.preview?.estimates.windowDays))
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }

            VStack(spacing: 0) {
                ForEach(store.offered) { change in
                    if change.id != store.offered.first?.id { CliniqueDivider() }
                    ThresholdChangeRow(
                        change: change,
                        isAccepted: store.isAccepted(change.field)
                    ) {
                        SharpitMotion.run(SharpitMotion.selection) { store.toggle(change.field) }
                    }
                }
            }

            Button(action: onApply) {
                Text(ThresholdSuggestionReadout.applyLabel(accepted: store.accepted.count, offered: store.offered.count))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
            .disabled(store.accepted.isEmpty)
        }
        .cliniqueCard(border: SharpitColor.statusWatchMark.opacity(0.5))
    }
}

/// One proposal: what moves, which way, from what to what, and whether it is kept.
private struct ThresholdChangeRow: View {
    let change: V1ThresholdChange
    let isAccepted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    (Text(change.label).foregroundStyle(SharpitColor.foreground)
                        + Text(" · ").foregroundStyle(SharpitColor.slate)
                        + Text(ThresholdSuggestionReadout.directionLabel(change.direction).lowercased())
                            .foregroundStyle(SharpitColor.pillarRecovery).fontWeight(.semibold))
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    (Text(change.from).strikethrough().foregroundStyle(SharpitColor.slate)
                        + Text(" ")
                        + Text(change.to).fontWeight(.semibold).foregroundStyle(SharpitColor.foreground))
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                }
                Spacer(minLength: SharpitSpacing.xs)
                Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(isAccepted ? SharpitColor.foreground : SharpitColor.outline)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(change.label), \(change.from) vers \(change.to)")
        .accessibilityAddTraits(isAccepted ? .isSelected : [])
    }
}

/// The card's words, kept apart so they are tested.
nonisolated enum ThresholdSuggestionReadout {
    /// « Capacité démontrée sur 120 jours, pas le record de toujours. »
    static func window(_ days: Int?) -> String {
        guard let days, days > 0 else { return String(localized: "Capacité démontrée récemment, pas le record de toujours.") }
        return String(localized: "Capacité démontrée sur \(days) jours, pas le record de toujours.")
    }

    /// « Appliquer », or « Appliquer (2) » when some proposals were left out.
    static func applyLabel(accepted: Int, offered: Int) -> String {
        accepted > 0 && accepted < offered ? String(localized: "Appliquer (\(accepted))") : String(localized: "Appliquer")
    }

    static func directionLabel(_ direction: V1ThresholdDirection) -> String {
        switch direction {
        case .up: String(localized: "Hausse")
        case .down: String(localized: "Baisse")
        case .set: String(localized: "Nouveau")
        }
    }
}
