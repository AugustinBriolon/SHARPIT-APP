import Charts
import SwiftUI

/// A body or health marker over time: the sparkline a tile draws, and the drawer a tile opens,
/// with the ranges the web keeps (`/api/v1/body/series`). Santé opens it from its markers
/// (SHARPIT ADR-053).

extension CorpsTone {
    /// The tone as a status, for the note's pill.
    var status: CliniqueStatus {
        switch self {
        case .neutral: .unknown
        case .inRange: .good
        case .belowRange: .watch
        }
    }

    var color: Color {
        switch self {
        case .neutral: SharpitColor.slate
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                        .fill(SharpitColor.slate.opacity(0.12))
                        .frame(height: 220)
                        .redacted(reason: .placeholder)
                } else {
                    Text("Pas encore assez de mesures sur cette période pour tracer une évolution.")
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.slate)
                }
                Text(reading.map { SanteReadout.explanation($0.key) } ?? metric.key.explanation)
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .background(SharpitColor.card)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(width: 44, height: 44)
                    .background(SharpitColor.tile, in: Circle())
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityLabel("Fermer")
            .padding(.trailing, 22)
            .padding(.top, 22)
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

    /// The marker's name, when and from where it was read, its figure, and its note as a pill.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(metric.key.label)
                .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.trailing, 56)
            VStack(alignment: .leading, spacing: 0) {
                Text(CorpsFormat.caption(metric))
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(metric.formattedValue)
                        .font(SharpitTypography.system(size: 52, weight: .semibold, relativeTo: .largeTitle, digits: true))
                        .tracking(-1.5)
                        .foregroundStyle(SharpitColor.foreground)
                    if let unit = metric.key.unit {
                        Text(unit)
                            .font(SharpitTypography.system(size: 19, weight: .regular, relativeTo: .title3))
                            .foregroundStyle(SharpitColor.slate)
                    }
                    Spacer(minLength: SharpitSpacing.xs)
                    if let note = metric.note {
                        CliniqueStatusPill(note, status: metric.tone.status)
                    }
                }
            }
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
            targetLabel: target.map { String(localized: "cible \(CorpsReadout.format($0, for: metric.key))") },
            axisName: metric.key.label,
            height: 220,
            redrawToken: redrawToken,
            axisLabel: { CorpsReadout.format($0, for: metric.key) },
            readout: { CorpsReadout.format($0, for: metric.key) + (metric.key.unit.map { " \($0)" } ?? "") }
        )
        .accessibilityLabel("\(metric.key.label), \(range.label)")
    }

    @ViewBuilder
    private var stats: some View {
        let values = points.map(\.value)
        if let low = values.min(), let high = values.max() {
            VStack(spacing: 0) {
                stat(String(localized: "Min"), CorpsReadout.format(low, for: metric.key) + unitSuffix)
                stat(String(localized: "Max"), CorpsReadout.format(high, for: metric.key) + unitSuffix)
                stat(String(localized: "Mesures"), "\(values.count)")
            }
        }
    }

    private var unitSuffix: String { metric.key.unit.map { " \($0)" } ?? "" }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            HStack {
                Text(label)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: SharpitSpacing.xs)
                Text(value)
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
            }
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
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
