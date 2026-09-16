import SwiftUI

struct OvernightGaugePair: View {
    let gauges: [OvernightGaugeModel]
    var pulseScores: Bool = false

    var body: some View {
        HStack(spacing: SharpitSpacing.xxs) {
            ForEach(gauges) { gauge in
                OvernightGaugeCell(gauge: gauge, pulse: pulseScores)
            }
        }
    }
}

private struct OvernightGaugeCell: View {
    let gauge: OvernightGaugeModel
    var pulse: Bool = false

    private var fraction: Double? {
        AnimatedScoreText.progressFraction(from: gauge.score)
    }

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ZStack {
                OvernightArcGauge(progress: fraction ?? 0, hasScore: fraction != nil)
                VStack(spacing: 2) {
                    AnimatedScoreText(score: gauge.score)
                        .opacity(pulse ? 0.55 : 1)
                    Text("sur 100")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .offset(y: 16)
            }
            .frame(height: 108)
            Text(title)
                .font(SharpitTypography.label())
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if let caption = gauge.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SharpitSpacing.cardPadding)
        .sharpitGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(gauge.score)")
    }

    private var title: String {
        switch gauge.key {
        case .sleep: "Score sommeil"
        case .recovery: "Score récupération"
        case .effort, .adaptation: gauge.key.instrumentLabel
        }
    }
}

/// Top semicircle: faded full track + darker fill that stops at score.
/// Uses `Circle.trim` (not `Path.addArc`) so partial progress never takes the long way around.
private struct OvernightArcGauge: View {
    let progress: Double
    var hasScore: Bool = true

    private let lineWidth: CGFloat = 12

    private var clamped: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = (side - lineWidth) / 2

            ZStack {
                semicircleTrack(trimEnd: 0.5)
                    .stroke(
                        Color.primary.opacity(0.16),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                if hasScore {
                    semicircleTrack(trimEnd: 0.5 * clamped)
                        .stroke(
                            Color.primary.opacity(0.9),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )

                    Circle()
                        .fill(SharpitInk.highlight)
                        .frame(width: 10, height: 10)
                        .offset(OvernightArcMath.tipOffset(progress: clamped, radius: radius))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// Bottom half of a circle, rotated 180° → top semicircle (left → top → right).
    private func semicircleTrack(trimEnd: CGFloat) -> some Shape {
        Circle()
            .trim(from: 0, to: trimEnd)
            .rotation(.degrees(180))
    }
}

enum OvernightArcMath {
    /// Tip on the top semicircle: progress 0 at left, 0.5 at top, 1 at right.
    static func tipOffset(progress: CGFloat, radius: CGFloat) -> CGSize {
        let t = Double(min(max(progress, 0), 1))
        let angle = Double.pi * (1 - t)
        return CGSize(
            width: radius * Foundation.cos(angle),
            height: -radius * Foundation.sin(angle)
        )
    }
}
