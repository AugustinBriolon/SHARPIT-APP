import SwiftUI

/// A score in its ring, the figure inside — Résumé's rings, read the same way on the home screen.
struct DialReadout: View {
    /// 0…100, or nil for an unread ring.
    let score: CGFloat?
    let figure: String
    var unit: String?
    var hue: Color = SharpitColor.pillarSleep

    var body: some View {
        WidgetRing(fraction: score.map { Double($0) / 100 }, hue: hue, lineWidth: 7)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(figure)
                        .font(SharpitTypography.gaugeScore)
                        .tracking(SharpitTypography.gaugeScoreTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .monospacedDigit()
                        .scaleEffect(DialFigureScale.factor(for: figure))
                    if let unit {
                        Text(unit)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
            }
            // The ring fits its height, so it is narrower than the card: centred, like its caption.
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
