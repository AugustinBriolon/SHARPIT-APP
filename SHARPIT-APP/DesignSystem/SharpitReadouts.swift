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
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            Text(caption)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
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
                    .foregroundStyle(SharpitColor.slate)
            }
            if let delta {
                SharpitPill(delta, style: deltaStyle)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
        }
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
                                  : SharpitColor.divider)
                            .frame(width: 10, height: 4)
                    }
                }
                Text("Confiance \(rounded) %")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Confiance \(rounded) pour cent")
        }
    }
}

