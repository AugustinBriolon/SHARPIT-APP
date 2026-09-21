import SwiftUI

/// A small measured value on a panel: caption on top, figure, optional note. Used in
/// rows of two or three on drill-down screens.
struct SharpitStatTile: View {
    let caption: String
    let value: String
    var unit: String?
    var note: String?
    var tone: Color = SharpitColor.foreground

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            Text(caption)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(SharpitTypography.data)
                    .tracking(SharpitTypography.dataTracking)
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            if let note {
                Text(note)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(2)
            }
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
    }
}

/// One reading of the coach, with the tone of what it says: a dot, a title, a line.
struct SharpitInsightRow: View {
    let title: String
    let detail: String
    let tone: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Circle()
                .fill(tone)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(detail)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// How sure the reading is, as a quiet closing line — the last step of the causal column.
struct SharpitConfidenceLine: View {
    let pct: Double?

    var body: some View {
        if let pct {
            let rounded = Int(pct.rounded())
            HStack(spacing: SharpitSpacing.xs) {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index < ConfidenceBars.filled(fromPct: rounded)
                                  ? SharpitColor.primary
                                  : SharpitColor.analysisGrid)
                            .frame(width: 10, height: 4)
                    }
                }
                Text("Confiance \(rounded) %")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Confiance \(rounded) pour cent")
        }
    }
}

/// The one number a drill-down is about, with the verdict it reads as.
struct SharpitHeroScore: View {
    let score: Double?
    let label: String
    let tone: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
            Text(score.map { "\(Int($0.rounded()))" } ?? "—")
                .font(SharpitTypography.heroScore)
                .tracking(SharpitTypography.heroScoreTracking)
                .foregroundStyle(score == nil ? SharpitColor.mutedForeground : tone)
                .contentTransition(.numericText())
                .animation(SharpitMotion.selection, value: score)
            Text("/100")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            Spacer(minLength: 0)
            Text(label)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(tone)
                .padding(.horizontal, SharpitSpacing.sm)
                .padding(.vertical, SharpitSpacing.xxs + 2)
                .background(tone.opacity(0.14), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}
