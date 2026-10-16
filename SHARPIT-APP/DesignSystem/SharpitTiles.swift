import SwiftUI

/// The ink squircle every card opens with: a lime glyph on ink (graphite on dark).
/// A sport, a metric or a section is told by this glyph — never by a colour (ADR-085).
struct SharpitIconTile: View {
    let symbol: String
    var size: CGFloat = SharpitTokens.tileSize

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * scale
        Image(systemName: symbol)
            .font(.system(size: side * 0.42, weight: .bold))
            .foregroundStyle(SharpitColor.inkAccent)
            .frame(width: side, height: side)
            .sharpitConcentricBackground(SharpitColor.inkSurface, minimum: SharpitRadius.tile * side / SharpitTokens.tileSize)
            .accessibilityHidden(true)
    }
}

/// An ordinal in a list of sets or exercises: a white numeral on a small ink squircle.
struct SharpitNumberChip: View {
    let number: Int

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = SharpitTokens.chipSize

    var body: some View {
        Text("\(number)")
            .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
            .foregroundStyle(SharpitColor.inkSurfaceForeground)
            .frame(width: side, height: side)
            .sharpitConcentricBackground(SharpitColor.inkSurface, minimum: SharpitRadius.small)
    }
}

/// A done mark: an ink check on a lime square. Empty, it is a quiet track square.
struct SharpitCheckBox: View {
    let isOn: Bool

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
            .fill(isOn ? SharpitColor.highlight : SharpitColor.track)
            .frame(width: side, height: side)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.48, weight: .bold))
                        .foregroundStyle(SharpitColor.highlightForeground)
                }
            }
            .accessibilityLabel(isOn ? "Fait" : "À faire")
    }
}

/// A short status word or delta in a capsule: « PR », « +5 kg », « ↑ 8 vs moy. ».
struct SharpitPill: View {
    enum Style {
        /// Lime fill, ink text — an achievement.
        case lime
        /// Neutral chip, ink text — a plain delta.
        case neutral
        /// Soft lime wash, olive text — a positive comparison.
        case limeSoft
        /// Ink fill, lime text — a score, apart from the lime states beside it.
        case ink
    }

    let text: String
    var style: Style = .neutral

    init(_ text: String, style: Style = .neutral) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(SharpitTypography.system(size: 14, weight: style == .limeSoft ? .medium : .bold, relativeTo: .subheadline, digits: true))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }

    private var foreground: Color {
        switch style {
        case .lime: SharpitColor.highlightForeground
        case .neutral: SharpitColor.foreground
        case .limeSoft: SharpitColor.accentForeground
        case .ink: SharpitColor.inkAccent
        }
    }

    private var background: Color {
        switch style {
        case .lime: SharpitColor.highlight
        case .neutral: SharpitColor.chipSurface
        case .limeSoft: SharpitColor.accent
        case .ink: SharpitColor.inkSurface
        }
    }
}
