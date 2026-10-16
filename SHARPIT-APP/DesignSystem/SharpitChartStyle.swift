import Charts
import SwiftUI

/// Swift Charts in the brand's dress (ADR-085): a lime line, hollow lime points, a lime wash
/// fading to nothing under it, dashed grid lines, and an ink bubble for the reading.
enum SharpitChartStyle {
    static let line = SharpitColor.highlight
    static let lineWidth: CGFloat = 3

    /// The wash under a line, lime to clear.
    static var area: LinearGradient {
        LinearGradient(
            colors: [SharpitColor.highlight.opacity(0.3), SharpitColor.highlight.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var gridStroke: StrokeStyle { StrokeStyle(lineWidth: 1, dash: [3, 3]) }
}

extension View {
    /// Dashed grid on both axes, muted labels.
    func sharpitChartAxes() -> some View {
        chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: SharpitChartStyle.gridStroke).foregroundStyle(SharpitColor.analysisBorder)
                AxisValueLabel().font(SharpitTypography.meta).foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: SharpitChartStyle.gridStroke).foregroundStyle(SharpitColor.analysisBorder)
            }
        }
    }
}

/// The reading on a chart: an ink bubble, white bold figure.
struct SharpitChartBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SharpitTypography.system(size: 15, weight: .bold, relativeTo: .subheadline, digits: true))
            .foregroundStyle(SharpitColor.inkSurfaceForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .sharpitConcentricBackground(SharpitColor.inkSurface, minimum: 10)
    }
}

/// A hollow lime point, for `.symbol { SharpitChartPoint() }` on a `PointMark`.
struct SharpitChartPoint: View {
    var body: some View {
        Circle()
            .fill(SharpitColor.card)
            .overlay(Circle().strokeBorder(SharpitColor.highlight, lineWidth: 3))
            .frame(width: 14, height: 14)
    }
}
