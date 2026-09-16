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
                .offset(y: 14)
            }
            .frame(height: 104)
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

/// Thick semicircle: muted track for unfinished range, solid fill for score.
private struct OvernightArcGauge: View {
    let progress: Double
    var hasScore: Bool = true

    private var clamped: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    var body: some View {
        ZStack {
            OvernightSemicircle(progress: 1)
                .stroke(
                    Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
            if hasScore {
                OvernightSemicircle(progress: clamped)
                    .stroke(
                        Color.primary.opacity(0.9),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                OvernightSemicircleTip(progress: clamped)
                    .fill(SharpitInk.highlight)
            }
        }
    }
}

/// Full semicircle from left (π) to right (0) through the top.
private struct OvernightSemicircle: Shape, Sendable {
    var progress: CGFloat = 1

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let geometry = OvernightArcGeometry(rect: rect)
        var path = Path()
        path.addArc(
            center: geometry.center,
            radius: geometry.radius,
            startAngle: .radians(.pi),
            endAngle: .radians(.pi * (1 - Double(progress))),
            clockwise: false
        )
        return path
    }
}

private struct OvernightSemicircleTip: Shape, Sendable {
    var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        guard progress > 0.01 else { return Path() }
        let geometry = OvernightArcGeometry(rect: rect)
        let angle = Double.pi * (1 - Double(progress))
        let point = CGPoint(
            x: geometry.center.x + geometry.radius * Foundation.cos(angle),
            y: geometry.center.y - geometry.radius * Foundation.sin(angle)
        )
        return Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
    }
}

private struct OvernightArcGeometry: Sendable {
    let center: CGPoint
    let radius: CGFloat

    nonisolated init(rect: CGRect) {
        radius = min(rect.width, rect.height) * 0.40
        center = CGPoint(x: rect.midX, y: rect.midY + radius * 0.32)
    }
}
