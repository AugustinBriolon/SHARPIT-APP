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

    /// The lines a session opens on, as the mock-up pairs them: the effort — power, or else
    /// pace — and the heart rate. Elevation and cadence wait in the legend.
    static func defaultSelection(from available: [ActivityChartMetric]) -> [ActivityChartMetric] {
        let effort: ActivityChartMetric? = available.contains(.power) ? .power : available.contains(.pace) ? .pace : nil
        let picked = [effort, ActivityChartMetric.heartRate].compactMap { $0 }.filter(available.contains)
        return picked.isEmpty ? Array(available.prefix(1)) : picked
    }
}

/// The session's curves on one plot, as the mock-up draws them: each chosen measure a line in
/// its own hue, on its own scale, over one time axis. The legend picks the measures; a finger on
/// the plot reads every one of them at that moment, and the table under it says what each adds
/// up to.
struct ActivityChartsSection: View {
    let samples: [V1ActivityStreamSample]
    let metrics: [ActivityChartMetric]
    @Binding var selection: [ActivityChartMetric]

    @State private var scrubbedMinute: Double?
    @State private var curves: [ActivityChartMetric: ActivityCurve]

    /// The curves are built here rather than on appearing: the plot's first frame already holds
    /// its lines, instead of an empty frame the chart fills a pass later.
    init(samples: [V1ActivityStreamSample], metrics: [ActivityChartMetric], selection: Binding<[ActivityChartMetric]>) {
        self.samples = samples
        self.metrics = metrics
        _selection = selection
        _curves = State(initialValue: Self.curves(for: metrics, samples: samples))
    }

    private var shownCurves: [ActivityCurve] {
        selection.compactMap { curves[$0] }
    }

    /// One time axis for every line, so a minute sits at the same x for each.
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                ActivitySectionTitle(ActivityCurve.title(for: selection))
                Spacer(minLength: SharpitSpacing.xs)
                if let scrubbedMinute {
                    Text(ActivityCurve.clock(scrubbedMinute * 60))
                        .font(SharpitTypography.system(size: 13, weight: .semibold, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityLabel(String(localized: "Instant lu"))
                        .accessibilityValue(ActivityCurve.clock(scrubbedMinute * 60))
                }
            }

            legend

            if shownCurves.isEmpty {
                Text("Pas assez de données pour afficher cette courbe.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.slate)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                plot
                summary
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { reconcile() }
        .onChange(of: samples) { _, _ in rebuild() }
        .onChange(of: metrics) { _, _ in reconcile() }
        .onChange(of: scrubbedMinute.map { Int($0 / notchStep) }) { _, notch in
            if notch != nil { SharpitHaptics.play(.notch(major: false)) }
        }
    }

    /// Each measure the session recorded: a stroke in its hue and its name, tapped to draw it or
    /// not. Under the finger, the name gives way to the value at that moment.
    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(metrics) { metric in
                    let isOn = selection.contains(metric)
                    Button { toggle(metric) } label: {
                        HStack(spacing: 6) {
                            Capsule()
                                .fill(isOn ? metric.tone : SharpitColor.outline)
                                .frame(width: 12, height: 2.5)
                            Text(reading(metric) ?? metric.label)
                                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                                .foregroundStyle(isOn ? SharpitColor.foreground : SharpitColor.slate)
                        }
                        .frame(minHeight: 32)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(metric.label)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    /// « 4:12 /km » while a finger is on the plot and the measure is drawn.
    private func reading(_ metric: ActivityChartMetric) -> String? {
        guard let scrubbedMinute, selection.contains(metric), let curve = curves[metric],
              let point = curve.point(nearest: scrubbedMinute)
        else { return nil }
        return "\(curve.reading(point.value)) \(metric.unit)"
    }

    private var plot: some View {
        Chart {
            ForEach(shownCurves, id: \.metric) { curve in
                ForEach(curve.points) { point in
                    LineMark(
                        x: .value(String(localized: "Temps"), point.minute),
                        y: .value(String(localized: "Niveau"), curve.level(of: point.value)),
                        series: .value(String(localized: "Mesure"), curve.metric.rawValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(curve.metric.tone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                if let scrubbedMinute, let point = curve.point(nearest: scrubbedMinute) {
                    PointMark(
                        x: .value(String(localized: "Temps"), point.minute),
                        y: .value(String(localized: "Niveau"), curve.level(of: point.value))
                    )
                    .foregroundStyle(curve.metric.tone)
                    .symbolSize(36)
                }
            }
            if let scrubbedMinute {
                RuleMark(x: .value(String(localized: "Temps"), scrubbedMinute))
                    .foregroundStyle(SharpitColor.outline)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartXScale(domain: minuteDomain)
        .chartYScale(domain: 0...1)
        .chartXSelection(value: $scrubbedMinute)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let minutes = value.as(Double.self), let whole = Int(exactly: minutes.rounded()) {
                        Text("\(whole)′")
                            .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption2, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
            }
        }
        .chartPlotStyle { $0.overlay(alignment: .bottom) { CliniqueDivider() } }
        .frame(height: 150)
        .accessibilityLabel(ActivityCurve.title(for: selection))
    }

    /// What each drawn measure adds up to: its average and its best.
    private var summary: some View {
        VStack(spacing: 0) {
            ForEach(Array(shownCurves.enumerated()), id: \.element.metric) { index, curve in
                if index > 0 { CliniqueDivider() }
                HStack(spacing: SharpitSpacing.sm) {
                    Text(curve.metric.label)
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer(minLength: SharpitSpacing.xs)
                    Text("\(curve.summary) \(curve.metric.unit)")
                        .foregroundStyle(SharpitColor.slate)
                }
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
            }
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
        curves = Self.curves(for: metrics, samples: samples)
        reconcile()
    }

    private static func curves(
        for metrics: [ActivityChartMetric],
        samples: [V1ActivityStreamSample]
    ) -> [ActivityChartMetric: ActivityCurve] {
        Dictionary(uniqueKeysWithValues: metrics.compactMap { metric in
            ActivityCurve(metric: metric, samples: samples).map { (metric, $0) }
        })
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

extension ActivityCurve {
    /// Where a value sits on the plot, 0 at the foot of the curve's own range and 1 at its top —
    /// each measure on its own scale, pace reversed so faster is higher.
    func level(of value: Double) -> Double {
        let domain = plottedDomain
        guard domain.upperBound > domain.lowerBound else { return 0.5 }
        return (plotted(value) - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
    }

    /// A label inside a sentence: lowercased, unless it is an acronym (« FC »).
    static func inSentence(_ label: String) -> String {
        label == label.uppercased() ? label : label.lowercased()
    }

    /// « Allure et FC » for two measures, the one's name alone, « Courbes » beyond.
    static func title(for selection: [ActivityChartMetric]) -> String {
        switch selection.count {
        case 1: selection[0].label
        case 2: String(localized: "\(selection[0].label) et \(ActivityCurve.inSentence(selection[1].label))")
        default: String(localized: "Courbes")
        }
    }
}

extension ActivityChartMetric {
    /// The measure's line on the plot: a chart mark, never text.
    var tone: Color {
        switch self {
        case .pace: SharpitColor.pillarSleep
        case .heartRate: SharpitColor.statusAlertMark
        case .power: SharpitColor.pillarCoach
        case .elevation: SharpitColor.slate
        case .cadence: SharpitColor.pillarNutrition
        }
    }
}
