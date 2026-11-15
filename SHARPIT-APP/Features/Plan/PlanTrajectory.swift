import SwiftUI

/// The two block-scale readings Plan carries under the week (SHARPIT IA, My week step 3):
/// Effort — what the load costs — and Adaptation — whether the body answers it. Each tile
/// pushes its day drill-down; overnight recovery stays on Résumé.
nonisolated enum PlanTrajectoryDestination: Hashable, Sendable {
    case effort
    case adaptation
}

/// Today's two readings, as last read. Either may be missing while it loads or if it failed:
/// the tile still opens its screen, which says why.
nonisolated struct PlanTrajectory: Equatable, Sendable {
    var effort: V1EffortResponse?
    var adaptation: V1AdaptationResponse?
}

/// What a trajectory tile reads, kept out of the view so it can be tested.
nonisolated struct PlanTrajectoryTile: Equatable, Sendable {
    let value: String
    let unit: String?
    let headline: String?
    let tone: V1SignalTone
    let caption: String?

    static func effort(_ effort: V1EffortResponse?) -> PlanTrajectoryTile {
        guard let effort else {
            return PlanTrajectoryTile(value: "—", unit: nil, headline: nil, tone: .neutral, caption: nil)
        }
        if let empty = effort.empty {
            return PlanTrajectoryTile(value: "—", unit: nil, headline: empty.title, tone: .neutral, caption: nil)
        }
        let score = effort.strain.score
        return PlanTrajectoryTile(
            value: score.map {
                $0.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.locale))
            } ?? "—",
            unit: score == nil ? nil : "/21",
            headline: effort.strain.label,
            tone: effort.strain.tone,
            caption: effort.verdict.label
        )
    }

    static func adaptation(_ adaptation: V1AdaptationResponse?) -> PlanTrajectoryTile {
        guard let adaptation else {
            return PlanTrajectoryTile(value: "—", unit: nil, headline: nil, tone: .neutral, caption: nil)
        }
        if let empty = adaptation.empty {
            return PlanTrajectoryTile(value: "—", unit: nil, headline: empty.title, tone: .neutral, caption: nil)
        }
        let trend = adaptation.trendLabel.trimmingCharacters(in: .whitespaces)
        return PlanTrajectoryTile(
            value: adaptation.index.map { "\(Int($0.rounded()))" } ?? "—",
            unit: adaptation.index == nil ? nil : "/100",
            headline: adaptation.status.label,
            tone: adaptation.status.tone,
            caption: trend.isEmpty || trend == "—" ? adaptation.verdict.label : trend
        )
    }
}

/// « Trajectoire » as a section of the week's sheet: Effort then Adaptation, a line each — the
/// reading as a status pill, the figure, and the way into its screen.
struct PlanTrajectoryCards: View {
    let trajectory: PlanTrajectory
    let onOpen: (PlanTrajectoryDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Trajectoire")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            line(String(localized: "Effort"), .effort(trajectory.effort)) { onOpen(.effort) }
            CliniqueDivider()
            line(String(localized: "Adaptation"), .adaptation(trajectory.adaptation)) { onOpen(.adaptation) }
        }
    }

    private func line(_ title: String, _ tile: PlanTrajectoryTile, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                    if let caption = tile.caption ?? (tile.unit == nil ? tile.headline : nil) {
                        Text(caption)
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(SharpitColor.slate)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: SharpitSpacing.xs)
                if tile.unit != nil, let headline = tile.headline {
                    CliniqueStatusPill(headline, status: RecoveryReadout.status(for: tile.tone))
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(tile.value)
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                        .foregroundStyle(tile.unit == nil ? SharpitColor.slate : SharpitColor.foreground)
                    if let unit = tile.unit {
                        Text(unit)
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
                .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
    }
}
