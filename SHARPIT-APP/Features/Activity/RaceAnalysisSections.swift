import SwiftUI

/// A raced session read leg by leg, in the order an athlete looks back on it: against the aim,
/// the heart rate of each leg, how the effort was spread, then what it cost.
struct RaceAnalysisSections: View {
    let analysis: V1RaceAnalysis
    /// The goal header above already carries the total against the aim.
    let showsTotal: Bool
    let onOpenLeg: ((String) -> Void)?

    @Environment(\.isExpertReading) private var isExpertReading

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            RaceObjectiveBlock(
                title: RaceAnalysisReadout.objectiveTitle(analysis),
                totalLine: showsTotal ? RaceAnalysisReadout.totalLine(analysis) : nil,
                segments: RaceAnalysisReadout.segments(analysis),
                rows: RaceAnalysisReadout.legRows(analysis),
                onOpenLeg: onOpenLeg
            )
            let zones = RaceAnalysisReadout.zoneRows(analysis)
            if !zones.isEmpty {
                RaceZonesBlock(rows: zones)
            }
            let effort = RaceAnalysisReadout.effortRows(analysis)
            if !effort.isEmpty {
                RaceFiguresBlock(title: "Gestion de l'effort", rows: effort)
            }
            let load = RaceAnalysisReadout.loadRows(analysis, isExpertReading: isExpertReading)
            if !load.isEmpty {
                RaceFiguresBlock(title: "Charge et récupération", rows: load)
            }
        }
    }
}

/// The legs against the aim: the bar, then a row per leg opening its own recording.
private struct RaceObjectiveBlock: View {
    let title: String
    let totalLine: String?
    let segments: [RaceLegSegment]
    let rows: [RaceLegRow]
    let onOpenLeg: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(title)
            if let totalLine {
                Text(totalLine)
                    .font(SharpitTypography.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)
            }
            if !segments.isEmpty {
                RaceLegsBar(segments: segments, compact: true)
            }
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    RaceLegRowLink(row: row, onOpen: onOpenLeg)
                    if row.id != rows.last?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

/// A leg's row; it opens the leg's recording when the server named one.
struct RaceLegRowLink: View {
    let row: RaceLegRow
    let onOpen: ((String) -> Void)?

    var body: some View {
        if let id = row.sourceActivityId, let onOpen {
            Button { onOpen(id) } label: { content(opens: true) }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Voir l’étape")
        } else {
            content(opens: false)
        }
    }

    private func content(opens: Bool) -> some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: row.segment.sport?.symbolName ?? "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(row.segment.sport.map { SharpitSportTone.label(for: $0) } ?? SharpitColor.mutedForeground)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.segment.label)
                    .font(row.segment.isTransition ? SharpitTypography.body : SharpitTypography.bodyEmphasis)
                    .foregroundStyle(row.segment.isTransition ? SharpitColor.mutedForeground : SharpitColor.foreground)
                if let detail = row.detail {
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            Text(RaceTime.clock(row.segment.durationSec))
                .font(SharpitTypography.instrument)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityLabel(RaceTime.spoken(row.segment.durationSec))
            if opens {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.5))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, SharpitSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Each leg's time in the five heart-rate zones, one thin bar per leg, the key once below.
struct RaceZonesBlock: View {
    let rows: [RaceZoneRow]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Zones cardiaques par étape")
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    HStack {
                        Text(row.label)
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Spacer(minLength: 0)
                        if let average = row.averageLine {
                            Text(average)
                                .font(SharpitTypography.meta)
                                .monospacedDigit()
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            ForEach(Array(row.shares.enumerated()), id: \.offset) { index, share in
                                Rectangle()
                                    .fill(SharpitZoneTone.color(index))
                                    .frame(width: proxy.size.width * share)
                            }
                        }
                    }
                    .frame(height: 6)
                    .clipShape(Capsule())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.spokenLabel)
            }
            HStack(spacing: SharpitSpacing.sm) {
                ForEach(0..<5, id: \.self) { index in
                    HStack(spacing: 4) {
                        Circle().fill(SharpitZoneTone.color(index)).frame(width: 6, height: 6)
                        Text("Z\(index + 1)")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

private struct RaceFiguresBlock: View {
    let title: String
    let rows: [ActivityTechnicalRow]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitEyebrow(title)
            ActivityTechnicalGrid(rows: rows)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}
