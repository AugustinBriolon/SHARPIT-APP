import Charts
import SwiftUI

/// One measure on one day, as a scrubbable chart reads it.
struct SharpitScrubPoint: Identifiable, Equatable {
    let date: Date
    let value: Double

    var id: Date { date }

    /// The measure closest in time to where the finger is.
    static func nearest(_ points: [SharpitScrubPoint], to date: Date) -> SharpitScrubPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// The app's one interactive chart: a line or bars over days, a finger on it reads the nearest
/// measure in a bubble, with an optional normal band and target. The curve draws itself left to
/// right on appearing, and again whenever `redrawToken` changes.
struct SharpitScrubChart: View {
    enum Kind { case line, bars }

    let points: [SharpitScrubPoint]
    var kind: Kind = .line
    /// The athlete's usual range, shaded behind a line.
    var band: ClosedRange<Double>?
    var target: Double?
    var targetLabel: String?
    /// The bar's colour for a value; ink by default.
    var barTint: (Double) -> Color = { _ in SharpitColor.primary }
    var axisName: String
    var yAxisStride: Double?
    var height: CGFloat = 160
    var redrawToken = 0
    var axisLabel: (Double) -> String
    var readout: (Double) -> String

    @State private var scrubbedDate: Date?
    @State private var drawProgress: CGFloat = 0
    @State private var dotScale: CGFloat = 0

    private var scrubbed: SharpitScrubPoint? {
        scrubbedDate.flatMap { SharpitScrubPoint.nearest(points, to: $0) }
    }

    var body: some View {
        Chart {
            if kind == .line { bandMark }
            targetMark
            ForEach(points) { point in
                switch kind {
                case .line:
                    LineMark(x: .value(String(localized: "Jour"), point.date), y: .value(axisName, point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(SharpitColor.primary)
                    PointMark(x: .value(String(localized: "Jour"), point.date), y: .value(axisName, point.value))
                        .foregroundStyle(SharpitColor.primary)
                        .symbolSize((points.count > 40 ? 6 : 22) * dotScale)
                case .bars:
                    BarMark(x: .value(String(localized: "Jour"), point.date, unit: .day), y: .value(axisName, point.value))
                        .foregroundStyle(barTint(point.value))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            if let scrubbed { selectionMarks(scrubbed) }
        }
        .chartXSelection(value: $scrubbedDate)
        .mask(alignment: .leading) {
            GeometryReader { geo in
                Rectangle().frame(width: geo.size.width * drawProgress)
            }
        }
        .modifier(ScrubYScale(kind: kind, values: domainValues))
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisValues) { value in
                AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(axisLabel(number)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: height)
        .accessibilityLabel(axisName)
        .onAppear(perform: draw)
        .onChange(of: redrawToken) { _, _ in
            drawProgress = 0
            dotScale = 0
            draw()
        }
        .onChange(of: points) { _, _ in scrubbedDate = nil }
        .onChange(of: scrubbed?.date) { _, date in
            if date != nil { SharpitHaptics.play(.notch(major: false)) }
        }
    }

    @ChartContentBuilder
    private var bandMark: some ChartContent {
        if let band, let first = points.first, let last = points.last {
            RectangleMark(
                xStart: .value(String(localized: "Début"), first.date),
                xEnd: .value(String(localized: "Fin"), last.date),
                yStart: .value(String(localized: "Bas"), band.lowerBound),
                yEnd: .value(String(localized: "Haut"), band.upperBound)
            )
            .foregroundStyle(SharpitColor.signalRecovery.opacity(0.12))
        }
    }

    @ChartContentBuilder
    private var targetMark: some ChartContent {
        if let target, target > 0 {
            RuleMark(y: .value(String(localized: "Cible"), target))
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    if let targetLabel {
                        Text(targetLabel)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
        }
    }

    @ChartContentBuilder
    private func selectionMarks(_ point: SharpitScrubPoint) -> some ChartContent {
        RuleMark(x: .value(String(localized: "Jour"), point.date))
            .foregroundStyle(SharpitColor.mutedForeground.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                bubble(point)
            }
        if kind == .line {
            PointMark(x: .value(String(localized: "Jour"), point.date), y: .value(axisName, point.value))
                .foregroundStyle(SharpitColor.primary)
                .symbolSize(90)
        }
    }

    private func bubble(_ point: SharpitScrubPoint) -> some View {
        VStack(spacing: 1) {
            Text(readout(point.value))
                .font(SharpitTypography.instrument)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.foreground)
            Text(point.date.sharpitFormatted(.dateTime.day().month(.abbreviated)))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .sharpitConcentricBackground(SharpitElevatedColor.panelOnSheet, minimum: SharpitRadius.small)
        .sharpitShadow(.control)
    }

    private var domainValues: [Double] {
        points.map(\.value) + [band?.lowerBound, band?.upperBound, target].compactMap { $0 }
    }

    private var yAxisValues: AxisMarkValues {
        yAxisStride.map { .stride(by: $0) } ?? .automatic
    }

    private func draw() {
        withAnimation(SharpitMotion.gaugeFill) { drawProgress = 1 }
        withAnimation(SharpitMotion.reveal.delay(SharpitMotion.reduceMotion ? 0 : 0.45)) { dotScale = 1 }
    }
}

/// Lines are never zero-based: these measures move by a few percent, and a zero axis would
/// flatten every real change. Bars keep the chart's own axis, which starts at zero.
private struct ScrubYScale: ViewModifier {
    let kind: SharpitScrubChart.Kind
    let values: [Double]

    func body(content: Content) -> some View {
        switch kind {
        case .line:
            content.chartYScale(domain: CorpsFormat.domain(values, padding: 0.08), range: .plotDimension(padding: 4))
        case .bars:
            content
        }
    }
}
