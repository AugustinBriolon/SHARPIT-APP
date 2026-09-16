import SwiftUI

struct OvernightGaugePair: View {
    let gauges: [OvernightGaugeModel]
    var revealed: Bool = true
    var pulseScores: Bool = false

    var body: some View {
        HStack(spacing: SharpitSpacing.xxs) {
            ForEach(Array(gauges.enumerated()), id: \.element.id) { index, gauge in
                OvernightGaugeCell(gauge: gauge, pulse: pulseScores)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 8)
                    .animation(
                        SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: index)),
                        value: revealed
                    )
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
                OvernightTickGauge(progress: 1, style: .track)
                if let fraction {
                    OvernightTickGauge(progress: fraction, style: .fill)
                }
                VStack(spacing: 2) {
                    AnimatedScoreText(score: gauge.score)
                        .opacity(pulse ? 0.55 : 1)
                    Text("sur 100")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .offset(y: 10)
            }
            .frame(height: 96)
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

private enum OvernightTickStyle {
    case track
    case fill
}

/// Semicircle tick gauge — geometry aligned with web overnight cards (π → 0).
private struct OvernightTickGauge: View {
    let progress: Double
    var style: OvernightTickStyle = .fill

    private static let tickCount = 52

    @State private var animated: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height * 0.72
            let radius = min(size.width, size.height) * 0.38
            let rInner = radius - 3
            let rOuter = radius + 3
            let start = Double.pi
            let end = 0.0
            let score = Double(animated) * 100

            for index in 0..<Self.tickCount {
                let t = Double(index) / Double(Self.tickCount - 1)
                let angle = start + (end - start) * t
                let tickScore = t * 100
                let lit = style == .track || tickScore <= score + 0.01
                guard lit || style == .track else { continue }

                var path = Path()
                path.move(
                    to: CGPoint(
                        x: cx + rInner * Foundation.cos(angle),
                        y: cy - rInner * Foundation.sin(angle)
                    )
                )
                path.addLine(
                    to: CGPoint(
                        x: cx + rOuter * Foundation.cos(angle),
                        y: cy - rOuter * Foundation.sin(angle)
                    )
                )

                let stroke: Color = {
                    switch style {
                    case .track:
                        return Color.primary.opacity(0.14)
                    case .fill where tickScore >= score - 14:
                        return SharpitInk.highlight.opacity(0.95)
                    case .fill:
                        return Color.primary.opacity(0.85)
                    }
                }()

                context.stroke(
                    path,
                    with: .color(stroke),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
            }
        }
        .onAppear { animate(to: CGFloat(min(max(progress, 0), 1))) }
        .onChange(of: progress) { _, newValue in
            animate(to: CGFloat(min(max(newValue, 0), 1)))
        }
    }

    private func animate(to value: CGFloat) {
        if style == .track || SharpitMotion.reduceMotion || reduceMotion {
            animated = value
            return
        }
        SharpitMotion.run(.easeOut(duration: SharpitMotion.countUpDuration)) {
            animated = value
        }
    }
}
