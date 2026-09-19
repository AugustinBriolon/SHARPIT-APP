import SwiftUI

/// Geometry of the overnight gauge, ported from the web's `overnight-gauge-geometry.ts`.
///
/// The values are the web's `viewBox` units (200 × 118) and are scaled to whatever width
/// the card gives. Keeping them identical is the point: this is the same instrument on
/// both surfaces, not a lookalike rebuilt from a screenshot.
enum SharpitTickGaugeGeometry {
    static let tickCount = 52
    static let boxWidth: CGFloat = 200
    static let boxHeight: CGFloat = 118
    static let centreX: CGFloat = 100
    static let centreY: CGFloat = 100
    static let radiusInner: CGFloat = 72
    static let radiusOuter: CGFloat = 78
    static let tickWidth: CGFloat = 1.6
    static let thumbRadius: CGFloat = 3.75

    /// Width / height of the gauge box.
    static let aspectRatio: CGFloat = boxWidth / boxHeight

    /// Where the score sits, as a fraction of the box height — the web's `top-[44%]`.
    static let readoutTopFraction: CGFloat = 0.44

    /// The score a tick stands for, 0…100.
    static func tickScore(at index: Int) -> CGFloat {
        guard tickCount > 1 else { return 100 }
        return CGFloat(index) / CGFloat(tickCount - 1) * 100
    }

    /// Angle of a tick, sweeping the top semicircle from π (left) to 0 (right).
    static func angle(at index: Int) -> CGFloat {
        guard tickCount > 1 else { return 0 }
        let t = CGFloat(index) / CGFloat(tickCount - 1)
        return .pi + (0 - .pi) * t
    }

    static func angle(forScore score: CGFloat) -> CGFloat {
        let t = min(max(score, 0), 100) / 100
        return .pi + (0 - .pi) * t
    }

    /// A point on the dial, in box units. Y grows downward, as in SVG.
    static func point(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: centreX + radius * Foundation.cos(angle),
            y: centreY - radius * Foundation.sin(angle)
        )
    }

    static func thumb(forScore score: CGFloat) -> CGPoint {
        point(angle: angle(forScore: score), radius: (radiusInner + radiusOuter) / 2)
    }
}

/// The overnight dial: 52 radial ticks, lit up to the score.
///
/// A thick stroked arc was the wrong instrument — it reads heavy at card width and left
/// no room around the number whatever the spacing. Ticks are 1.6 units wide against a
/// 78-unit radius, which is what makes the web version look like a readout.
struct SharpitTickGauge: View {
    /// 0…100, or nil for an unread dial.
    let score: CGFloat?

    var body: some View {
        Canvas { context, size in
            let scale = size.width / SharpitTickGaugeGeometry.boxWidth

            for index in 0..<SharpitTickGaugeGeometry.tickCount {
                let angle = SharpitTickGaugeGeometry.angle(at: index)
                let inner = SharpitTickGaugeGeometry.point(
                    angle: angle,
                    radius: SharpitTickGaugeGeometry.radiusInner
                )
                let outer = SharpitTickGaugeGeometry.point(
                    angle: angle,
                    radius: SharpitTickGaugeGeometry.radiusOuter
                )

                var path = Path()
                path.move(to: CGPoint(x: inner.x * scale, y: inner.y * scale))
                path.addLine(to: CGPoint(x: outer.x * scale, y: outer.y * scale))

                context.stroke(
                    path,
                    with: .color(SharpitTickTone.stroke(at: index, score: score)),
                    style: StrokeStyle(
                        lineWidth: SharpitTickGaugeGeometry.tickWidth * scale,
                        lineCap: .round
                    )
                )
            }

            guard let score, score > 0.5 else { return }
            let thumb = SharpitTickGaugeGeometry.thumb(forScore: score)
            let radius = SharpitTickGaugeGeometry.thumbRadius * scale
            let dot = Path(
                ellipseIn: CGRect(
                    x: thumb.x * scale - radius,
                    y: thumb.y * scale - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            context.fill(dot, with: .color(SharpitColor.highlight))
            context.stroke(
                dot,
                with: .color(SharpitColor.highlightForeground),
                style: StrokeStyle(lineWidth: scale)
            )
        }
        .aspectRatio(SharpitTickGaugeGeometry.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Tick colours, mirroring the web's `overnightTickStroke`.
enum SharpitTickTone {
    /// Ticks within this many points below the score take the highlight, so the dial
    /// brightens as it approaches the reading instead of ending on a hard edge.
    static let highlightBand: CGFloat = 14

    static func stroke(at index: Int, score: CGFloat?) -> Color {
        guard let score else { return SharpitColor.analysisBorder }

        let tickScore = SharpitTickGaugeGeometry.tickScore(at: index)
        if tickScore > score { return SharpitColor.analysisBorder }
        if tickScore >= score - highlightBand { return SharpitColor.highlight }
        return SharpitColor.foreground
    }
}
