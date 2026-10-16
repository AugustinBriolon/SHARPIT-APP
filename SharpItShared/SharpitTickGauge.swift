import SwiftUI

/// Geometry of the score dial (ADR-085): a 270° sweep of heavy ticks, open at the bottom,
/// in a 200 × 168 box scaled to whatever width the card gives.
enum SharpitTickGaugeGeometry {
    static let tickCount = 56
    static let boxWidth: CGFloat = 200
    static let boxHeight: CGFloat = 168
    static let centreX: CGFloat = 100
    static let centreY: CGFloat = 92
    static let radiusInner: CGFloat = 66
    static let radiusOuter: CGFloat = 80
    /// Ticks past the score are shorter: the unlit part of the dial recedes.
    static let radiusInnerUnlit: CGFloat = 72
    static let tickWidth: CGFloat = 3.6
    static let thumbRadius: CGFloat = 6
    /// The sweep, from bottom-left (225°) clockwise over the top to bottom-right (−45°).
    static let startAngle: CGFloat = .pi * 5 / 4
    static let endAngle: CGFloat = -.pi / 4

    /// Width / height of the gauge box.
    static let aspectRatio: CGFloat = boxWidth / boxHeight

    /// The dial's centre as a fraction of the box — where a readout's own centre belongs.
    static let centreFraction = CGPoint(x: centreX / boxWidth, y: centreY / boxHeight)

    /// Where the « 0 » and « 100 » scale labels sit, in box units.
    static let scaleLabelY: CGFloat = 160

    static func tickScore(at index: Int) -> CGFloat {
        guard tickCount > 1 else { return 100 }
        return CGFloat(index) / CGFloat(tickCount - 1) * 100
    }

    /// Angle of a tick along the sweep.
    static func angle(at index: Int) -> CGFloat {
        guard tickCount > 1 else { return startAngle }
        let t = CGFloat(index) / CGFloat(tickCount - 1)
        return startAngle + (endAngle - startAngle) * t
    }

    static func angle(forScore score: CGFloat) -> CGFloat {
        let t = min(max(score, 0), 100) / 100
        return startAngle + (endAngle - startAngle) * t
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

/// The score dial: heavy ink ticks up to the score, a lime band and knob at the reading,
/// short track ticks after it, and optional « 0 » / « 100 » at the open ends.
///
/// Animatable: a change of score inside an animation sweeps the ticks one by one rather than
/// redrawing the dial at its new value.
struct SharpitTickGauge: View, Animatable {
    /// 0…100, or nil for an unread dial.
    var score: CGFloat?
    /// Draws the thumb at 0 too — a progress dial shows where it starts; a readout at 0 does not.
    var showsThumbAtStart = false
    /// Writes « 0 » and « 100 » under the open ends of the dial.
    var showsScale = false

    var animatableData: CGFloat {
        get { score ?? 0 }
        set { if score != nil { score = newValue } }
    }

    var body: some View {
        Canvas { context, size in
            let scale = size.width / SharpitTickGaugeGeometry.boxWidth

            for index in 0..<SharpitTickGaugeGeometry.tickCount {
                let angle = SharpitTickGaugeGeometry.angle(at: index)
                let inner = SharpitTickGaugeGeometry.point(
                    angle: angle,
                    radius: SharpitTickTone.isLit(at: index, score: score)
                        ? SharpitTickGaugeGeometry.radiusInner
                        : SharpitTickGaugeGeometry.radiusInnerUnlit
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

            if showsScale {
                for (label, x) in [("0", 0.22), ("100", 0.78)] {
                    context.draw(
                        Text(label)
                            .font(.system(size: 12 * max(scale, 0.8), weight: .medium).monospacedDigit())
                            .foregroundStyle(SharpitColor.mutedForeground),
                        at: CGPoint(x: size.width * x, y: SharpitTickGaugeGeometry.scaleLabelY * scale)
                    )
                }
            }

            guard let score, score > 0.5 || showsThumbAtStart else { return }
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
            // A card-coloured ring cuts the knob out of the ticks, so it reads as one crisp dot.
            let ring = Path(ellipseIn: CGRect(
                x: thumb.x * scale - radius * 1.5,
                y: thumb.y * scale - radius * 1.5,
                width: radius * 3,
                height: radius * 3
            ))
            context.fill(ring, with: .color(SharpitColor.card))
            context.fill(dot, with: .color(SharpitColor.highlight))
        }
        .aspectRatio(SharpitTickGaugeGeometry.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Centres `content` on the dial's centre, not the box's: the sweep is open at the bottom,
    /// so the box's middle sits below the arc's and a figure placed there reads low.
    func sharpitDialCentre<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let content = content()
        return overlay {
            GeometryReader { proxy in
                content
                    .frame(maxWidth: proxy.size.width * 0.66)
                    .position(
                        x: proxy.size.width * SharpitTickGaugeGeometry.centreFraction.x,
                        y: proxy.size.height * SharpitTickGaugeGeometry.centreFraction.y
                    )
            }
        }
    }
}

/// Tick colours (ADR-085): ink up to the score, lime for the last stretch before it,
/// track after it.
enum SharpitTickTone {
    /// Ticks within this many points below the score take the lime, so the dial brightens
    /// as it reaches the reading instead of ending on a hard edge.
    static let highlightBand: CGFloat = 14

    static func isLit(at index: Int, score: CGFloat?) -> Bool {
        guard let score else { return false }
        return SharpitTickGaugeGeometry.tickScore(at: index) <= score
    }

    static func stroke(at index: Int, score: CGFloat?) -> Color {
        guard let score else { return SharpitColor.track }

        let tickScore = SharpitTickGaugeGeometry.tickScore(at: index)
        if tickScore > score { return SharpitColor.track }
        if tickScore >= score - highlightBand { return SharpitColor.highlight }
        return SharpitColor.foreground
    }
}
