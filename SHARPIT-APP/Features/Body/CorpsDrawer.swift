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
                LineMark(x: .value(String(localized: "Jour"), point.date), y: .value(String(localized: "Valeur"), point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
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
    /// Bumped when a new range arrives, so the curve draws anew.
    @State private var redrawToken = 0

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
            isLoading = false
            // The first answer refines the curve already drawn from the tile; a new range draws anew.
            guard loaded != nil else {
                SharpitMotion.run { loaded = fetched }
                return
            }
            loaded = fetched
            redrawToken += 1
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
        SharpitScrubChart(
            points: points.map { SharpitScrubPoint(date: $0.date, value: $0.value) },
            band: metric.baseline,
            target: target,
            targetLabel: target.map { "cible \(CorpsReadout.format($0, for: metric.key))" },
            axisName: metric.key.label,
            height: 220,
            redrawToken: redrawToken,
            axisLabel: { CorpsReadout.format($0, for: metric.key) },
            readout: { CorpsReadout.format($0, for: metric.key) + (metric.key.unit.map { " \($0)" } ?? "") }
        )
        .padding(SharpitSpacing.md)
        .sharpitSurface(.panel)
        .accessibilityLabel("\(metric.key.label), \(range.label)")
    }

    @ViewBuilder
    private var stats: some View {
        let values = points.map(\.value)
        if let low = values.min(), let high = values.max() {
            HStack(spacing: SharpitSpacing.sm) {
                SharpitStatTile(caption: String(localized: "Min"), value: CorpsReadout.format(low, for: metric.key), unit: metric.key.unit)
                SharpitStatTile(caption: String(localized: "Max"), value: CorpsReadout.format(high, for: metric.key), unit: metric.key.unit)
                SharpitStatTile(caption: String(localized: "Mesures"), value: "\(values.count)")
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
        case .year: String(localized: "1 an")
        case .all: String(localized: "Tout")
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
