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
                $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
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

struct PlanTrajectoryCards: View {
    let trajectory: PlanTrajectory
    let onOpen: (PlanTrajectoryDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Trajectoire")
            HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                Button { onOpen(.effort) } label: {
                    PlanTrajectoryTileView(
                        title: "Effort",
                        symbol: "bolt",
                        tile: .effort(trajectory.effort)
                    )
                }
                .buttonStyle(.sharpitPressable)

                Button { onOpen(.adaptation) } label: {
                    PlanTrajectoryTileView(
                        title: "Adaptation",
                        symbol: "arrow.triangle.2.circlepath",
                        tile: .adaptation(trajectory.adaptation)
                    )
                }
                .buttonStyle(.sharpitPressable)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PlanTrajectoryTileView: View {
    let title: String
    let symbol: String
    let tile: PlanTrajectoryTile

    private var tone: Color { RecoveryReadout.tone(for: tile.tone) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(title: title, symbol: symbol, tint: SharpitColor.primary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(tile.value)
                        .font(SharpitTypography.data)
                        .tracking(SharpitTypography.dataTracking)
                        .foregroundStyle(tile.unit == nil ? SharpitColor.mutedForeground : tone)
                        .contentTransition(.numericText())
                    if let unit = tile.unit {
                        Text(unit)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                if let headline = tile.headline {
                    Text(headline)
                        .font(SharpitTypography.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(tile.unit == nil ? SharpitColor.mutedForeground : tone)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 0)
            if let caption = tile.caption {
                SharpitTelemetryCapsule(lead: caption)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
