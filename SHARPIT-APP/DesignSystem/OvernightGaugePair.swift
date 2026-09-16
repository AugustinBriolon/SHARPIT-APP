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
                OvernightArcGauge(progress: fraction ?? 0, hasScore: fraction != nil)
                VStack(spacing: 2) {
                    AnimatedScoreText(score: gauge.score)
                        .opacity(pulse ? 0.55 : 1)
                    Text("sur 100")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .offset(y: 12)
            }
            .frame(height: 100)
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

/// Continuous semicircle stroke (π → 0) with light tick underlay.
private struct OvernightArcGauge: View {
    let progress: Double
    var hasScore: Bool = true

    @State private var animated: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OvernightTickUnderlay()
                .opacity(0.35)
            OvernightSemicircle()
                .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            if hasScore {
                OvernightSemicircle(progress: animated)
                    .stroke(
                        Color.primary.opacity(0.88),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                OvernightSemicircleTip(progress: animated)
                    .fill(SharpitInk.highlight)
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
        return Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
    }
}

private struct OvernightTickUnderlay: View {
    private static let tickCount = 26

    var body: some View {
        Canvas { context, size in
            let geometry = OvernightArcGeometry(rect: CGRect(origin: .zero, size: size))
            let rInner = geometry.radius - 7
            let rOuter = geometry.radius - 2
            for index in 0..<Self.tickCount {
                let t = Double(index) / Double(Self.tickCount - 1)
                let angle = Double.pi * (1 - t)
                var path = Path()
                path.move(
                    to: CGPoint(
                        x: geometry.center.x + rInner * Foundation.cos(angle),
                        y: geometry.center.y - rInner * Foundation.sin(angle)
                    )
                )
                path.addLine(
                    to: CGPoint(
                        x: geometry.center.x + rOuter * Foundation.cos(angle),
                        y: geometry.center.y - rOuter * Foundation.sin(angle)
                    )
                )
                context.stroke(
                    path,
                    with: .color(.primary.opacity(0.18)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
            }
        }
    }
}

private struct OvernightArcGeometry: Sendable {
    let center: CGPoint
    let radius: CGFloat

    nonisolated init(rect: CGRect) {
        radius = min(rect.width, rect.height) * 0.42
        center = CGPoint(x: rect.midX, y: rect.midY + radius * 0.28)
    }
}
