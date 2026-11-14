import SwiftUI

/// The round neutral tile every card opens with: an ink glyph on the tile tone.
/// A sport, a metric or a section is told by this glyph — never by a colour.
struct SharpitIconTile: View {
    let symbol: String
    var size: CGFloat = SharpitTokens.tileSize

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * scale
        Image(systemName: symbol)
            .font(.system(size: side * 0.42, weight: .regular))
            .foregroundStyle(SharpitColor.foreground)
            .frame(width: side, height: side)
            .background(SharpitColor.tile, in: Circle())
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

/// A done mark: a check on an ink square. Empty, it is an outlined tile.
struct SharpitCheckBox: View {
    let isOn: Bool

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
            .fill(isOn ? SharpitColor.primary : SharpitColor.tile)
            .frame(width: side, height: side)
            // An empty box needs its edge: the tile tone alone is lost on the sheet.
            .overlay(RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous).strokeBorder(isOn ? Color.clear : SharpitColor.outline, lineWidth: 1))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.48, weight: .semibold))
                        .foregroundStyle(SharpitColor.primaryForeground)
                }
            }
            .accessibilityLabel(isOn ? String(localized: "Fait") : String(localized: "À faire"))
    }
}

/// A short status word or delta in a capsule: « PR », « +5 kg », « ↑ 8 vs moy. ».
struct SharpitPill: View {
    enum Style {
        /// The good status set — an achievement.
        case lime
        /// Neutral tile, ink text — a plain delta.
        case neutral
        /// The good status set — a positive comparison.
        case limeSoft
        /// Ink fill — a score, apart from the states beside it.
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
            .font(SharpitTypography.system(size: 14, weight: style == .limeSoft ? .regular : .semibold, relativeTo: .subheadline, digits: true))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .lineLimit(1)
            .fixedSize()
    }

    /// A good reading carries its border, as every status set does; the others have none.
    private var border: Color {
        switch style {
        case .lime, .limeSoft: SharpitColor.statusGoodBorder
        case .neutral, .ink: .clear
        }
    }

    private var foreground: Color {
        switch style {
        case .lime, .limeSoft: SharpitColor.statusGoodForeground
        case .neutral: SharpitColor.foreground
        case .ink: SharpitColor.primaryForeground
        }
    }

    private var background: Color {
        switch style {
        case .lime, .limeSoft: SharpitColor.statusGood
        case .neutral: SharpitColor.tile
        case .ink: SharpitColor.primary
        }
    }
}
