import SwiftUI

/// A small measured value: the figure first, bold, its unit muted beside it, then what it
/// is in a quiet line under it — the stat row of the references (ADR-085).
struct SharpitStatTile: View {
    let caption: String
    let value: String
    var unit: String?
    var note: String?
    var tone: Color = SharpitColor.foreground
    /// Flat inside a card (the stat row under a chart); a card of its own on the canvas.
    var isFlat = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(SharpitTypography.data)
                    .tracking(SharpitTypography.dataTracking)
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(SharpitTypography.system(size: 15, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Text(caption)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let note {
                Text(note)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(2)
            }
        }
        .padding(isFlat ? 0 : SharpitSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if !isFlat { Color.clear.sharpitSurface(.panel) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A hero figure with its unit and an optional delta pill: « 102.5 kg  +5 kg ».
struct SharpitHeroFigure: View {
    let value: String
    var unit: String?
    var delta: String?
    var deltaStyle: SharpitPill.Style = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
            Text(value)
                .font(SharpitTypography.heroScore)
                .tracking(SharpitTypography.heroScoreTracking)
                .foregroundStyle(SharpitColor.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit {
                Text(unit)
                    .font(SharpitTypography.unit)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            if let delta {
                SharpitPill(delta, style: deltaStyle)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
        }
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
                                  : SharpitColor.track)
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
    /// The top of the scale: 100 for a score, 21 for the day's strain.
    var scale: Int = 100
    /// Decimals shown — a 0–21 strain reads to the tenth, a score whole.
    var fractionDigits: Int = 0

    private var figure: String {
        guard let score else { return "—" }
        guard fractionDigits > 0 else { return "\(Int(score.rounded()))" }
        return score.formatted(
            .number.precision(.fractionLength(fractionDigits)).locale(Locale(identifier: "fr_FR"))
        )
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
            Text(figure)
                .font(SharpitTypography.heroScore)
                .tracking(SharpitTypography.heroScoreTracking)
                .foregroundStyle(score == nil ? SharpitColor.mutedForeground : SharpitColor.foreground)
                .contentTransition(.numericText())
                .animation(SharpitMotion.selection, value: score)
            Text("/\(scale)")
                .font(SharpitTypography.unit)
                .foregroundStyle(SharpitColor.mutedForeground)
            Spacer(minLength: 0)
            Text(label)
                .font(SharpitTypography.system(size: 14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(SharpitColor.chipSurface, in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}
