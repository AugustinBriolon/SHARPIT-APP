import SwiftUI

/// The app's tick dial with its figure set inside the arc — Résumé's overnight gauges, and the
/// food log's energy, read the same way on the home screen.
struct DialReadout: View {
    /// 0…100, or nil for an unread dial.
    let score: CGFloat?
    let figure: String
    var unit: String?

    var body: some View {
        SharpitTickGauge(score: score)
            // The dial fits its height, so it is narrower than the card: centred, not left, like its caption.
            .frame(maxWidth: .infinity, alignment: .center)
            .sharpitDialCentre {
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
            }
    }
}
