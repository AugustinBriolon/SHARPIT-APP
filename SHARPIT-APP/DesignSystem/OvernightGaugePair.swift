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
                OvernightTickArc(progress: 1, opacity: 0.12)
                if let fraction {
                    OvernightTickArc(progress: fraction, opacity: 0.9)
                }
                VStack(spacing: 2) {
                    AnimatedScoreText(score: gauge.score)
                        .opacity(pulse ? 0.55 : 1)
                    Text("sur 100")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 88)
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

private struct OvernightTickArc: View {
    let progress: Double
    var opacity: Double = 1

    @State private var animated: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: true)) { _ in
            Canvas { context, size in
                let inset: CGFloat = 8
                let rect = CGRect(
                    x: inset,
                    y: inset,
                    width: size.width - inset * 2,
                    height: size.height - inset * 2
                )
                let path = Path(ellipseIn: rect)
                context.stroke(
                    path.trimmedPath(from: 0.55, to: 0.55 + 0.4 * animated),
                    with: .color(.primary.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
            }
        }
        .onAppear { animate(to: CGFloat(min(max(progress, 0), 1))) }
        .onChange(of: progress) { _, newValue in
            animate(to: CGFloat(min(max(newValue, 0), 1)))
        }
    }

    private func animate(to value: CGFloat) {
        if SharpitMotion.reduceMotion || reduceMotion {
            animated = value
            return
        }
        SharpitMotion.run(.easeOut(duration: SharpitMotion.countUpDuration)) {
            animated = value
        }
    }
}
