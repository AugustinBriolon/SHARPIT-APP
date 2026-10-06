import SwiftUI

/// Two medians on one axis — without and with — joined by the gap between them, each day behind
/// them as a faint dot on its own lane. Every row of a domain shares the axis, so gaps compare by
/// length. Positions are 0–100, already placed by the server.
///
/// The gap carries the tone; a weak association draws it dashed. No animation: the figures are a
/// reading, not news.
struct SharpitDumbbellTrack: View {
    let withoutPct: Double
    let withPct: Double
    var withDaysPct: [Double] = []
    var withoutDaysPct: [Double] = []
    var gridPct: [Double] = []
    let tone: Color
    var dashed = false

    private let height: CGFloat = 30
    private let median: CGFloat = 11
    private let day: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let inset = median / 2
            let width = size.width - median
            func x(_ pct: Double) -> CGFloat { inset + width * CGFloat(min(max(pct, 0), 100) / 100) }
            let mid = size.height / 2

            for pct in gridPct {
                var line = Path()
                line.move(to: CGPoint(x: x(pct), y: 0))
                line.addLine(to: CGPoint(x: x(pct), y: size.height))
                context.stroke(line, with: .color(SharpitColor.analysisGrid), lineWidth: SharpitStroke.hairline)
            }

            // Days without on the upper lane, days with on the lower one.
            for pct in withoutDaysPct {
                context.fill(dot(at: CGPoint(x: x(pct), y: mid - 9), size: day), with: .color(SharpitColor.mutedForeground.opacity(0.35)))
            }
            for pct in withDaysPct {
                context.fill(dot(at: CGPoint(x: x(pct), y: mid + 9), size: day), with: .color(tone.opacity(0.4)))
            }

            var gap = Path()
            gap.move(to: CGPoint(x: x(withoutPct), y: mid))
            gap.addLine(to: CGPoint(x: x(withPct), y: mid))
            context.stroke(
                gap,
                with: .color(tone.opacity(0.7)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dashed ? [4, 4] : [])
            )

            let without = dot(at: CGPoint(x: x(withoutPct), y: mid), size: median)
            context.fill(without, with: .color(SharpitColor.card))
            context.stroke(without, with: .color(SharpitColor.mutedForeground), lineWidth: 2)
            context.fill(dot(at: CGPoint(x: x(withPct), y: mid), size: median), with: .color(tone))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func dot(at center: CGPoint, size: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
    }
}

#Preview {
    SharpitDumbbellTrack(
        withoutPct: 52,
        withPct: 23,
        withDaysPct: [11, 23, 28],
        withoutDaysPct: [52, 44, 61],
        gridPct: [0, 33, 67, 100],
        tone: SharpitColor.signalCaution
    )
    .padding()
}
