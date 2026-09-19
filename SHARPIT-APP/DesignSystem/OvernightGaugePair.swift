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
        // Three tiers, three gaps: inside the score block, between the label and its
        // caption, and a larger one separating the bowl from the words under it. They
        // were all `xxs` before, which is why the arc, the label and the caption read
        // as one crowded block.
        VStack(spacing: SharpitSpacing.sm) {
            OvernightArcGauge(progress: displayedProgress) {
                VStack(spacing: SharpitSpacing.xxs) {
                    AnimatedScoreText(score: gauge.score, animation: SharpitMotion.gaugeFill)
                        .opacity(pulse ? 0.55 : 1)
                    Text("sur 100")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(OvernightGaugeLayout.bowlAspectRatio, contentMode: .fit)
            // The arc is stroked with a round cap, so without this inset the two
            // ends sit flush against the panel's hairline.
            .padding(.horizontal, SharpitSpacing.xs)

            VStack(spacing: SharpitSpacing.xxs) {
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

/// Top semicircle — faded full track, darker fill stopping at the score, and whatever
/// the caller puts in the bowl.
///
/// The score used to be a sibling view offset by a fraction of the *box* height while the
/// arc sized itself from the *width*. The two could not stay in proportion: change the
/// box and the number drifted toward the arc. Both now derive from one radius.
private struct OvernightArcGauge<Content: View>: View {
    let progress: CGFloat
    @ViewBuilder let content: Content

    private let lineWidth = OvernightGaugeLayout.arcLineWidth
    private let tipSize: CGFloat = 10

    private var clamped: CGFloat {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            // The radius answers to both dimensions. Deriving it from the width alone
            // made the arc taller than its own box, so the apex overflowed upward and
            // sat on the panel's edge.
            let pathRadius = max(
                0,
                min(
                    geo.size.width / 2 - lineWidth / 2,
                    geo.size.height - lineWidth
                )
            )
            let diameter = pathRadius * 2
            let baseline = geo.size.height - lineWidth / 2

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
            .position(x: geo.size.width / 2, y: baseline)

            // Centred in the bowl: the midpoint between the apex and the baseline.
            // Anything else — a fixed offset, a fraction of the box — leaves the gap
            // above the number and the gap below it unequal, which is what read as
            // crushed however much air the box itself had.
            content
                .position(
                    x: geo.size.width / 2,
                    y: baseline - OvernightGaugeLayout.scoreCentre(radius: pathRadius)
                )
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
    /// Stroke width of the arc, shared with the layout math below.
    static let arcLineWidth: CGFloat = 12

    /// Air kept between the arc's apex and the top of the bowl.
    static let apexAir: CGFloat = SharpitSpacing.md

    /// Width / height of the arc+score bowl.
    ///
    /// The bowl must clear the radius plus the stroke's cap plus `apexAir`, which is
    /// `width / 2 + apexAir`. A ratio cannot express an additive term, so it is chosen to
    /// satisfy the inequality at the *narrowest* width a two-up row produces — a value
    /// tuned to one width leaves the narrow case with no air at all. Earlier values were
    /// picked first and the geometry made to fit them, so the arc either overflowed the
    /// top (2.05) or had to be shrunk onto the score.
    static let bowlAspectRatio: CGFloat = 1.55

    /// How far above the baseline the score block is centred.
    ///
    /// Half the radius is the midpoint of the bowl, which leaves the same air above the
    /// number as below it. The score reads as sitting *in* the arc rather than hanging
    /// from it.
    static func scoreCentre(radius: CGFloat) -> CGFloat {
        radius / 2
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
