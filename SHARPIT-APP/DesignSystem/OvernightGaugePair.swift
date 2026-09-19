import SwiftUI

struct OvernightGaugePair: View {
    let gauges: [OvernightGaugeModel]
    var pulseScores: Bool = false

    var body: some View {
        HStack(spacing: SharpitSpacing.xs) {
            ForEach(gauges) { gauge in
                OvernightGaugeCell(gauge: gauge, pulse: pulseScores)
            }
        }
    }
}

private struct OvernightGaugeCell: View {
    let gauge: OvernightGaugeModel
    var pulse: Bool = false

    @State private var displayedProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var targetFraction: CGFloat {
        CGFloat(AnimatedScoreText.progressFraction(from: gauge.score) ?? 0)
    }

    var body: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            GeometryReader { geo in
                let bowlHeight = geo.size.height
                let lift = OvernightGaugeLayout.scoreLift(bowlHeight: bowlHeight)

                ZStack(alignment: .bottom) {
                    OvernightArcGauge(progress: displayedProgress)

                    VStack(spacing: 1) {
                        AnimatedScoreText(score: gauge.score, animation: SharpitMotion.gaugeFill)
                            .opacity(pulse ? 0.55 : 1)
                        Text("sur 100")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .offset(y: -lift)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(OvernightGaugeLayout.bowlAspectRatio, contentMode: .fit)

            Text(title)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            if let caption = gauge.caption {
                Text(caption)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(gauge.score)")
        .onAppear { animateFill(to: targetFraction) }
        .onChange(of: gauge.score) { _, _ in
            animateFill(to: targetFraction)
        }
    }

    private func animateFill(to value: CGFloat) {
        if SharpitMotion.reduceMotion || reduceMotion {
            displayedProgress = value
            return
        }
        SharpitMotion.run(SharpitMotion.gaugeFill) {
            displayedProgress = value
        }
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
private struct OvernightArcGauge: View {
    let progress: CGFloat

    private let lineWidth: CGFloat = 12
    private let tipSize: CGFloat = 10

    private var clamped: CGFloat {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let diameter = geo.size.width
            let pathRadius = diameter / 2

            ZStack {
                semicircle(trimEnd: 0.5)
                    .stroke(
                        SharpitColor.radialTrack,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                semicircle(trimEnd: 0.5 * clamped)
                    .stroke(
                        SharpitColor.primary,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                // Animatable progress → tip stays on the arc (not a Cartesian chord).
                OvernightArcTip(progress: clamped, radius: pathRadius, size: tipSize)
            }
            .frame(width: diameter, height: diameter)
            .position(x: geo.size.width / 2, y: geo.size.height - lineWidth / 2)
        }
    }

    private func semicircle(trimEnd: CGFloat) -> some Shape {
        Circle()
            .trim(from: 0, to: trimEnd)
            .rotation(.degrees(180))
    }
}

/// Tip whose `animatableData` is progress, so SwiftUI interpolates the angle
/// and recomputes polar offset each frame (avoids chord shortcuts through the bowl).
private struct OvernightArcTip: View, Animatable {
    var progress: CGFloat
    var radius: CGFloat
    var size: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Circle()
            .fill(SharpitColor.primary)
            .frame(width: size, height: size)
            .offset(OvernightArcMath.tipOffset(progress: progress, radius: radius))
            // At zero there is no progress to mark, and a dot parked on the left
            // cap reads as a stray mark rather than as an empty gauge.
            .opacity(progress > 0 ? 1 : 0)
            .accessibilityHidden(true)
    }
}

enum OvernightGaugeLayout {
    /// Width / height of the arc+score bowl (≈ 2φ / φ… kept optical, not strict φ).
    static let bowlAspectRatio: CGFloat = 2.05
    /// Approximate score + "sur 100" block height used for lift math.
    static let scoreBlockHeight: CGFloat = 44

    /// Lift score from the diameter into the bowl (minor φ segment of free air).
    static func scoreLift(bowlHeight: CGFloat, scoreBlockHeight: CGFloat = scoreBlockHeight) -> CGFloat {
        let free = max(0, bowlHeight - scoreBlockHeight)
        return SharpitRatio.minor(of: free)
    }
}

enum OvernightArcMath {
    static func tipOffset(progress: CGFloat, radius: CGFloat) -> CGSize {
        let t = Double(min(max(progress, 0), 1))
        let angle = Double.pi * (1 - t)
        return CGSize(
            width: radius * Foundation.cos(angle),
            height: -radius * Foundation.sin(angle)
        )
    }
}
