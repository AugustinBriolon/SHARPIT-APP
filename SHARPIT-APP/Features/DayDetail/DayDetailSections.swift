import SwiftUI

/// A warning the day carries — overreaching, a plateau — in its tone, above the reading.
struct DayDetailAlert: View {
    let label: String
    let tone: Color

    var body: some View {
        Label(label, systemImage: "exclamationmark.triangle.fill")
            .font(SharpitTypography.bodyEmphasis)
            .foregroundStyle(tone)
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous))
    }
}

/// The reading's reasons, one arrow each — the recommendation step of the causal column.
struct DayDetailRationale: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                    Image(systemName: "arrow.right")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.primary)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// « Ce qui l'explique »: the facts the reading stands on.
struct DayDetailEvidenceSection: View {
    let evidence: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Ce qui l'explique")
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                ForEach(evidence, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                        Circle()
                            .fill(SharpitColor.primary)
                            .frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(line)
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
    }
}

/// One dimension of a reading: its name and what it covers, the score in its tone with the
/// server's word for it, and a bar. A dimension without a signal says so instead of a zero.
struct DayDetailDimensionRow: View {
    let label: String
    let description: String
    let available: Bool
    let score: Double?
    let tone: Color
    /// The server's word for the score — « Élevée » — when it has one.
    var intensity: String? = nil
    /// « Frein », « Dominante » — what marks this dimension out.
    var tag: String? = nil

    private var fraction: Double { min(max((score ?? 0) / 100, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text(label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(available ? SharpitColor.foreground : SharpitColor.mutedForeground)
                if let tag {
                    SharpitInlineTag(tag)
                }
                Spacer(minLength: SharpitSpacing.xs)
                if available, let score {
                    if let intensity {
                        Text(intensity)
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(tone)
                    }
                    Text("\(Int(score.rounded()))")
                        .font(SharpitTypography.instrument)
                        .foregroundStyle(tone)
                        .monospacedDigit()
                } else {
                    Text("Signal manquant")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Text(description)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SharpitColor.analysisGrid)
                    if available, score != nil {
                        Capsule()
                            .fill(tone)
                            .frame(width: geo.size.width * fraction)
                    }
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The closing line of a reading: how sure it is, and what it stands on.
struct DayDetailConfidenceFooter: View {
    let pct: Double?
    let note: String

    var body: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            SharpitConfidenceLine(pct: pct)
            Text(note)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .frame(maxWidth: .infinity)
    }
}
