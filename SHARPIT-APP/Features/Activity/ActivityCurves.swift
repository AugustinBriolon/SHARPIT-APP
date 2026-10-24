import Charts
import SwiftUI

/// One measure of a session over its time, thinned for drawing, with what it adds up to.
/// Samples are evenly spaced in time (the server thins one recording), so a plain mean is the
/// session's average.
struct ActivityCurve: Equatable {
    struct Point: Identifiable, Equatable {
        let id: Int
        /// Minutes since the start.
        let minute: Double
        let value: Double
    }

    let metric: ActivityChartMetric
    let points: [Point]
    let average: Double
    /// The best of the session: the highest, or for pace the fastest (its 2nd percentile, so
    /// one GPS jump does not set it).
    let peak: Double

    /// A lane draws at most this many points: a long ride's thousands of samples are wider than
    /// the screen and only cost layout.
    static let maxPoints = 240

    init?(metric: ActivityChartMetric, samples: [V1ActivityStreamSample], maxPoints: Int = ActivityCurve.maxPoints) {
        let raw: [(minute: Double, value: Double)] = samples.compactMap { sample in
            guard let value = metric.value(for: sample), value.isFinite, sample.t.isFinite else { return nil }
            return (sample.t / 60, value)
        }
        guard raw.count > 1 else { return nil }
        self.metric = metric

        let bucketCount = Swift.min(Swift.max(maxPoints, 2), raw.count)
        var points: [Point] = []
        points.reserveCapacity(bucketCount)
        for bucket in 0..<bucketCount {
            let start = bucket * raw.count / bucketCount
            let end = Swift.max(start + 1, (bucket + 1) * raw.count / bucketCount)
            let slice = raw[start..<end]
            let count = Double(slice.count)
            points.append(Point(
                id: bucket,
                minute: slice.reduce(0) { $0 + $1.minute } / count,
                value: slice.reduce(0) { $0 + $1.value } / count
            ))
        }
        self.points = points

        let values = raw.map(\.value)
        switch metric {
        case .pace:
            // Mean pace over-weights the slow stretches; the pace of the mean speed does not.
            let meanSpeed = values.reduce(0) { $0 + 1_000 / $1 } / Double(values.count)
            average = 1_000 / meanSpeed
            let sorted = values.sorted()
            peak = sorted[Int(Double(sorted.count - 1) * 0.02)]
        case .heartRate, .power, .elevation, .cadence:
            average = values.reduce(0, +) / Double(values.count)
            peak = values.max() ?? average
        }
    }

    /// Faster is higher: pace is drawn on a reversed axis by plotting its negative.
    func plotted(_ value: Double) -> Double { metric == .pace ? -value : value }

    func unplotted(_ value: Double) -> Double { metric == .pace ? -value : value }

    /// The plotted range with air above and below; never zero-based, a curve moves by percents.
    var plottedDomain: ClosedRange<Double> {
        let values = points.map { plotted($0.value) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let margin = high == low ? Swift.max(abs(high) * 0.08, 1) : (high - low) * 0.12
        let lower = metric == .pace ? low - margin : Swift.max(0, low - margin)
        return lower...(high + margin)
    }

    var minuteDomain: ClosedRange<Double> {
        guard let first = points.first?.minute, let last = points.last?.minute, first < last else { return 0...1 }
        return first...last
    }

    /// The point drawn closest to a minute, for the finger's reading.
    func point(nearest minute: Double) -> Point? {
        points.min { abs($0.minute - minute) < abs($1.minute - minute) }
    }

    /// What a lane says while no finger is on it: « moy. 148 · max 176 ».
    var summary: String {
        let peakWord = metric == .pace ? String(localized: "meilleure") : String(localized: "max")
        return String(localized: "moy. \(reading(average)) · \(peakWord) \(reading(peak))")
    }

    /// A value in the lane's unit, which is written beside it — so pace without « /km ».
    func reading(_ value: Double) -> String {
        metric == .pace ? ActivityCurve.clock(value) : metric.formatted(value)
    }

    /// A value on the lane's axis — pace as a bare clock, without « /km ».
    func axisLabel(plotted value: Double) -> String {
        reading(unplotted(value))
    }

    /// « 5:12 », « 1:02:30 » — a duration or a pace in seconds; « — » for what is not a time.
    static func clock(_ seconds: Double) -> String {
        guard let total = Int(exactly: seconds.rounded()), total >= 0 else { return "—" }
        let hours = total / 3_600, minutes = total % 3_600 / 60, rest = total % 60
        return hours > 0
            ? "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", rest))"
            : "\(minutes):\(String(format: "%02d", rest))"
    }

    /// The lanes a session opens on: heart rate, then power or else pace, then elevation.
    static func defaultSelection(from available: [ActivityChartMetric]) -> [ActivityChartMetric] {
        let effort: ActivityChartMetric? = available.contains(.power) ? .power : available.contains(.pace) ? .pace : nil
        let picked = [ActivityChartMetric.heartRate, effort, .elevation].compactMap { $0 }.filter(available.contains)
        return picked.isEmpty ? Array(available.prefix(1)) : picked
    }
}

/// « Courbes »: one lane per chosen measure, stacked on one time axis. A finger on any lane
/// reads every lane at that moment, so heart rate, pace and the climb are read together rather
/// than as two curves fighting over one plot.
struct ActivityChartsSection: View {
    let samples: [V1ActivityStreamSample]
    let metrics: [ActivityChartMetric]
    @Binding var selection: [ActivityChartMetric]

    @State private var scrubbedMinute: Double?
    @State private var curves: [ActivityChartMetric: ActivityCurve] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shownCurves: [ActivityCurve] {
        selection.compactMap { curves[$0] }
    }

    /// One time axis for every lane, so a minute sits at the same x in each.
    private var minuteDomain: ClosedRange<Double> {
        let domains = shownCurves.map(\.minuteDomain)
        guard let low = domains.map(\.lowerBound).min(), let high = domains.map(\.upperBound).max(), low < high else { return 0...1 }
        return low...high
    }

    /// The finger's notch: about forty across the session, however long it was.
    private var notchStep: Double {
        Swift.max((minuteDomain.upperBound - minuteDomain.lowerBound) / 40, 0.25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(title: String(localized: "Courbes"), symbol: "waveform.path.ecg", showsChevron: false) {
                if let scrubbedMinute {
                    Text(ActivityCurve.clock(scrubbedMinute * 60))
                        .font(SharpitTypography.instrument)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityLabel(String(localized: "Instant lu"))
                        .accessibilityValue(ActivityCurve.clock(scrubbedMinute * 60))
                }
            }

            if metrics.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SharpitSpacing.xs) {
                        ForEach(metrics) { metric in
                            Button { toggle(metric) } label: {
                                ActivityMetricToggleLabel(metric: metric, isSelected: selection.contains(metric))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection.contains(metric) ? .isSelected : [])
                        }
                    }
                }
                // Scrolls edge to edge of the card and clips there: unclipped, the chips slid out of it.
                .contentMargins(.horizontal, SharpitSpacing.cardPadding, for: .scrollContent)
                .padding(.horizontal, -SharpitSpacing.cardPadding)
            }

            if shownCurves.isEmpty {
                Text("Pas assez de données pour afficher cette courbe.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(spacing: SharpitSpacing.md) {
                    ForEach(Array(shownCurves.enumerated()), id: \.element.metric) { index, curve in
                        ActivityCurveLane(
                            curve: curve,
                            minuteDomain: minuteDomain,
                            showsTimeAxis: index == shownCurves.count - 1,
                            stacksHeader: dynamicTypeSize.isAccessibilitySize,
                            scrubbedMinute: $scrubbedMinute
                        )
                    }
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .onAppear { rebuild() }
        .onChange(of: samples) { _, _ in rebuild() }
        .onChange(of: metrics) { _, _ in reconcile() }
        .onChange(of: scrubbedMinute.map { Int($0 / notchStep) }) { _, notch in
            if notch != nil { SharpitHaptics.play(.notch(major: false)) }
        }
    }

    private func toggle(_ metric: ActivityChartMetric) {
        SharpitMotion.run(SharpitMotion.selection) {
            if let index = selection.firstIndex(of: metric) {
                // The last lane stays: an empty card says nothing.
                if selection.count > 1 { selection.remove(at: index) }
            } else {
                // Lanes keep the menu's order, whatever order they were picked in.
                selection = metrics.filter { selection.contains($0) || $0 == metric }
            }
        }
    }

    private func rebuild() {
        var built: [ActivityChartMetric: ActivityCurve] = [:]
        for metric in metrics {
            built[metric] = ActivityCurve(metric: metric, samples: samples)
        }
        curves = built
        reconcile()
    }

    /// Keeps the selection to what this session recorded, so a ride without heart rate opens on
    /// its own curves instead of an empty card.
    private func reconcile() {
        selection = selection.filter { metrics.contains($0) }
        if selection.isEmpty {
            selection = ActivityCurve.defaultSelection(from: metrics)
        }
    }
}

/// One measure's lane: its name and what it adds up to — or, under the finger, its value at that
/// moment — over an ink line on a lime wash.
private struct ActivityCurveLane: View {
    let curve: ActivityCurve
    let minuteDomain: ClosedRange<Double>
    let showsTimeAxis: Bool
    let stacksHeader: Bool
    @Binding var scrubbedMinute: Double?

    private var scrubbed: ActivityCurve.Point? {
        scrubbedMinute.flatMap { curve.point(nearest: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            header
            chart
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(curve.metric.label)
        .accessibilityValue("\(curve.summary) \(curve.metric.unit)")
    }

    @ViewBuilder private var header: some View {
        let layout = stacksHeader
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs))
        layout {
            Text(curve.metric.label)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            if !stacksHeader { Spacer(minLength: 0) }
            if let scrubbed {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(curve.reading(scrubbed.value))
                        .font(SharpitTypography.instrument)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                    Text(curve.metric.unit)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            } else {
                Text("\(curve.summary) \(curve.metric.unit)")
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    private var chart: some View {
        let domain = curve.plottedDomain
        return Chart {
            ForEach(curve.points) { point in
                AreaMark(
                    x: .value(String(localized: "Temps"), point.minute),
                    yStart: .value(curve.metric.unit, domain.lowerBound),
                    yEnd: .value(curve.metric.unit, curve.plotted(point.value))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(SharpitChartStyle.area)
                LineMark(
                    x: .value(String(localized: "Temps"), point.minute),
                    y: .value(curve.metric.unit, curve.plotted(point.value))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(SharpitColor.foreground)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let scrubbedMinute {
                RuleMark(x: .value(String(localized: "Temps"), scrubbedMinute))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            if let scrubbed {
                PointMark(
                    x: .value(String(localized: "Temps"), scrubbed.minute),
                    y: .value(curve.metric.unit, curve.plotted(scrubbed.value))
                )
                .symbol { SharpitChartPoint() }
            }
        }
        .chartXScale(domain: minuteDomain)
        .chartYScale(domain: domain)
        .chartXSelection(value: $scrubbedMinute)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: SharpitChartStyle.gridStroke).foregroundStyle(SharpitColor.analysisGrid)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(curve.axisLabel(plotted: number))
                            .font(SharpitTypography.meta)
                            .monospacedDigit()
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: SharpitChartStyle.gridStroke).foregroundStyle(SharpitColor.analysisGrid)
                if showsTimeAxis {
                    AxisValueLabel {
                        if let minutes = value.as(Double.self), let whole = Int(exactly: minutes.rounded()) {
                            Text("\(whole)′")
                                .font(SharpitTypography.meta)
                                .monospacedDigit()
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                }
            }
        }
        .frame(height: showsTimeAxis ? 112 : 92)
    }
}

private struct ActivityMetricToggleLabel: View {
    let metric: ActivityChartMetric
    let isSelected: Bool

    var body: some View {
        Text(metric.label)
            .font(SharpitTypography.bodyEmphasis.weight(.semibold))
            .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
            .padding(.horizontal, SharpitSpacing.sm)
            .frame(minHeight: SharpitSpacing.minimumTouchTarget)
            .background(isSelected ? SharpitColor.primary : SharpitColor.chipSurface, in: Capsule())
            .contentShape(Capsule())
    }
}
