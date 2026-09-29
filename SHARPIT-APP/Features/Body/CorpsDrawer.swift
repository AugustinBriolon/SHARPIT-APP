import Charts
import SwiftUI

/// A body or health marker over time: the sparkline a tile draws, and the drawer a tile opens,
/// with the ranges the web keeps (`/api/v1/body/series`). Santé opens it from its markers
/// (SHARPIT ADR-053).

extension CorpsTone {
    var color: Color {
        switch self {
        case .neutral: SharpitColor.mutedForeground
        case .inRange: SharpitColor.signalRecovery
        case .belowRange: SharpitColor.signalCaution
        }
    }
}

/// A trend at a glance: no axes, no labels — the drawer carries those.
struct CorpsSparkline: View {
    let points: [CorpsPoint]
    let tone: Color

    var body: some View {
        if points.count > 1 {
            Chart(points) { point in
                LineMark(x: .value("Jour", point.date), y: .value("Valeur", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: CorpsFormat.domain(points.map(\.value), padding: 0.1))
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Drawer

/// A metric's evolution: the latest value, a chart over a chosen range, the band when there is
/// one, and what the number is.
struct CorpsMetricDrawer: View {
    let metric: CorpsMetric
    /// Drawn across the chart — the weight target, when the athlete set one.
    var target: Double? = nil
    /// Santé's reading of the marker — its norm and its month — when opened from Santé.
    var reading: V1HealthMarker? = nil
    /// The range's points, from the web's series route.
    let loadSeries: (CorpsRange) async -> [CorpsPoint]

    @Environment(\.dismiss) private var dismiss
    @State private var range: CorpsRange = .ninetyDays
    @State private var loaded: [CorpsPoint]?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    header
                    if let reading {
                        SanteReadingBlock(marker: reading)
                    }
                    SharpitSegmentedControl(
                        selection: $range,
                        options: CorpsRange.allCases.map {
                            SharpitSegmentedControl<CorpsRange>.Option(value: $0, label: $0.label)
                        }
                    )
                    if points.count > 1 {
                        chart
                        stats
                    } else if isLoading {
                        RoundedRectangle(cornerRadius: SharpitRadius.panel)
                            .fill(SharpitColor.mutedForeground.opacity(0.12))
                            .frame(height: 220)
                            .redacted(reason: .placeholder)
                    } else {
                        Text("Pas encore assez de mesures sur cette période pour tracer une évolution.")
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    Text(reading.map { SanteReadout.explanation($0.key) } ?? metric.key.explanation)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SharpitSpacing.pageInset)
            }
            .navigationTitle(metric.key.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
        .task(id: range) {
            isLoading = true
            let fetched = await loadSeries(range)
            SharpitMotion.run { loaded = fetched }
            isLoading = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            HStack(alignment: .lastTextBaseline, spacing: SharpitSpacing.xs) {
                Text(metric.formattedValue)
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(SharpitColor.foreground)
                if let unit = metric.key.unit {
                    Text(unit)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            if let note = metric.note {
                Text(note)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(metric.tone.color)
            }
            Text(CorpsFormat.caption(metric))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }

    /// The web's series once it answered; until then, what the tile already holds.
    private var points: [CorpsPoint] {
        loaded ?? range.filter(metric.series)
    }

    private var chart: some View {
        let shown = points
        let values = shown.map(\.value) + [metric.baseline?.lowerBound, metric.baseline?.upperBound, target].compactMap { $0 }
        return Chart {
            if let band = metric.baseline, let first = shown.first, let last = shown.last {
                RectangleMark(
                    xStart: .value("Début", first.date),
                    xEnd: .value("Fin", last.date),
                    yStart: .value("Bas", band.lowerBound),
                    yEnd: .value("Haut", band.upperBound)
                )
                .foregroundStyle(SharpitColor.signalRecovery.opacity(0.12))
            }
            if let target, target > 0 {
                RuleMark(y: .value("Cible", target))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("cible \(CorpsReadout.format(target, for: metric.key))")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
            }
            ForEach(shown) { point in
                LineMark(x: .value("Jour", point.date), y: .value(metric.key.label, point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(SharpitColor.primary)
                PointMark(x: .value("Jour", point.date), y: .value(metric.key.label, point.value))
                    .foregroundStyle(SharpitColor.primary)
                    .symbolSize(shown.count > 40 ? 6 : 22)
            }
        }
        // Never zero-based: these measures move by a few percent, and a zero axis would
        // flatten every real change.
        .chartYScale(domain: CorpsFormat.domain(values, padding: 0.08), range: .plotDimension(padding: 4))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(CorpsReadout.format(number, for: metric.key))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 220)
        .padding(SharpitSpacing.md)
        .sharpitSurface(.panel)
        .animation(SharpitMotion.reveal, value: range)
        .accessibilityLabel("\(metric.key.label), \(range.label)")
    }

    @ViewBuilder
    private var stats: some View {
        let values = points.map(\.value)
        if let low = values.min(), let high = values.max() {
            HStack(spacing: SharpitSpacing.sm) {
                SharpitStatTile(caption: "Min", value: CorpsReadout.format(low, for: metric.key), unit: metric.key.unit)
                SharpitStatTile(caption: "Max", value: CorpsReadout.format(high, for: metric.key), unit: metric.key.unit)
                SharpitStatTile(caption: "Mesures", value: "\(values.count)")
            }
        }
    }
}

nonisolated enum CorpsRange: String, CaseIterable, Identifiable, Sendable {
    case thirtyDays
    case ninetyDays
    case year
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thirtyDays: "30 j"
        case .ninetyDays: "90 j"
        case .year: "1 an"
        case .all: "Tout"
        }
    }

    var days: Int? {
        switch self {
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .year: 365
        case .all: nil
        }
    }

    /// The points inside the range, counted back from the latest one rather than from today,
    /// so a scale unused for a month still shows its last weeks.
    func filter(_ points: [CorpsPoint]) -> [CorpsPoint] {
        guard let days, let last = points.last else { return points }
        let cutoff = last.date.addingTimeInterval(-Double(days) * 24 * 3600)
        return points.filter { $0.date >= cutoff }
    }
}

enum CorpsFormat {
    /// « 21 septembre · Withings » — when and from where, whichever is known.
    static func caption(_ metric: CorpsMetric) -> String {
        let when = metric.measuredAt?.sharpitFormatted(.dateTime.day().month(.wide))
        return [when, metric.source].compactMap { $0 }.joined(separator: " · ")
    }

    /// Padding either side so a flat series still has room, never a zero-based axis.
    static func domain(_ values: [Double], padding: Double) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let span = max(high - low, abs(high) * 0.02, 0.5)
        return (low - span * padding)...(high + span * padding)
    }
}
