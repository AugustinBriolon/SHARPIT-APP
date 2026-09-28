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
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(figure)
                            .font(SharpitTypography.gaugeScore)
                            .tracking(SharpitTypography.gaugeScoreTracking)
                            .foregroundStyle(SharpitColor.foreground)
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                        if let unit {
                            Text(unit)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .offset(y: proxy.size.height * SharpitTickGaugeGeometry.readoutTopFraction)
                }
            }
    }
}
