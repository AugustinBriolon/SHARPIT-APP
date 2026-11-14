import Charts
import SwiftUI

/// How « Tendances » draws two markers on one chart: each on its own scale, so a heart rate and
/// a weight can be read together.
enum SanteTrendReadout {
    /// A series on its own span, 0 at its lowest and 1 at its highest; a flat one sits mid-height.
    static func normalised(_ points: [CorpsPoint]) -> [CorpsPoint] {
        guard let low = points.map(\.value).min(), let high = points.map(\.value).max() else { return [] }
        guard high > low else { return points.map { CorpsPoint(date: $0.date, value: 0.5) } }
        return points.map { CorpsPoint(date: $0.date, value: ($0.value - low) / (high - low)) }
    }

    /// The markers a trend can be drawn for: those with at least three readings this month.
    static func drawable(_ markers: [V1HealthMarker]) -> [V1HealthMarker] {
        markers.filter { $0.series.count > 2 }
    }

    /// « 16 sept. »
    static func day(_ date: Date) -> String {
        date.sharpitFormatted(.dateTime.day().month(.abbreviated))
    }
}

/// « Tendances »: a marker's month as a line over its area, another laid over it with
/// « Comparer », and the last reading named in a bubble.
struct SanteTrends: View {
    let markers: [V1HealthMarker]

    @State private var shownKey: V1HealthMarker.Key?
    @State private var comparedKey: V1HealthMarker.Key?

    private var shown: V1HealthMarker? {
        markers.first { $0.key == shownKey } ?? markers.first { $0.key == .vo2max } ?? markers.first
    }

    private var compared: V1HealthMarker? {
        markers.first { $0.key == comparedKey && $0.key != shown?.key }
    }

    var body: some View {
        if let shown {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tendances")
                            .font(SharpitTypography.sectionTitle)
                            .tracking(SharpitTypography.sectionTitleTracking)
                            .foregroundStyle(SharpitColor.foreground)
                            .accessibilityAddTraits(.isHeader)
                        Menu {
                            Picker("Repère", selection: Binding(get: { shown.key }, set: { shownKey = $0 })) {
                                ForEach(markers) { Text(SanteReadout.title($0.key)).tag($0.key) }
                            }
                        } label: {
                            (Text(SanteReadout.title(shown.key))
                                + Text(SanteReadout.trend(shown).map { " · \($0)" } ?? ""))
                                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                                .foregroundStyle(SharpitColor.slate)
                                .lineLimit(1)
                        }
                        .accessibilityHint("Choisit le repère affiché")
                    }
                    Spacer(minLength: SharpitSpacing.sm)
                    if markers.count > 1 {
                        Menu {
                            Picker("Comparer", selection: $comparedKey) {
                                Text("Aucun").tag(V1HealthMarker.Key?.none)
                                ForEach(markers.filter { $0.key != shown.key }) {
                                    Text(SanteReadout.title($0.key)).tag(V1HealthMarker.Key?.some($0.key))
                                }
                            }
                        } label: {
                            Text(compared.map { SanteReadout.title($0.key) } ?? String(localized: "Comparer"))
                                .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .subheadline))
                                .foregroundStyle(SharpitColor.foreground)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .overlay(Capsule().strokeBorder(SharpitColor.outline, lineWidth: 1))
                        }
                    }
                }
                chart(shown)
            }
        }
    }

    private func chart(_ shown: V1HealthMarker) -> some View {
        let line = SanteTrendReadout.normalised(shown.series)
        let other = compared.map { SanteTrendReadout.normalised($0.series) } ?? []
        let value = SanteReadout.value(shown)
        return Chart {
            ForEach(line) { point in
                AreaMark(x: .value("Jour", point.date), y: .value("Niveau", point.value))
                    .foregroundStyle(SharpitColor.pillarSleep.opacity(0.1))
                LineMark(x: .value("Jour", point.date), y: .value("Niveau", point.value), series: .value("Repère", "a"))
                    .foregroundStyle(SharpitColor.pillarSleep)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            ForEach(other) { point in
                LineMark(x: .value("Jour", point.date), y: .value("Niveau", point.value), series: .value("Repère", "b"))
                    .foregroundStyle(SharpitColor.pillarNutrition)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            if let last = line.last {
                RuleMark(x: .value("Jour", last.date))
                    .foregroundStyle(SharpitColor.outline)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(x: .value("Jour", last.date), y: .value("Niveau", last.value))
                    .foregroundStyle(SharpitColor.pillarSleep)
                    .symbolSize(36)
                    .annotation(position: .topLeading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SanteTrendReadout.day(last.date))
                                .foregroundStyle(SharpitColor.slate)
                            Text([value.text, value.unit].compactMap { $0 }.joined(separator: " "))
                                .fontWeight(.semibold)
                                .foregroundStyle(SharpitColor.foreground)
                        }
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SharpitColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SharpitColor.divider, lineWidth: 1))
                    }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: -0.15...1.5)
        .chartLegend(.hidden)
        .frame(height: 124)
        .accessibilityLabel("\(SanteReadout.title(shown.key)) sur le mois")
    }
}

/// A table of Santé: its name, the column heads, then one row per marker — name, status, value.
struct SanteTable: View {
    struct Row: Identifiable {
        let id: String
        let name: String
        var status: (word: String, status: CliniqueStatus)? = nil
        let value: String
    }

    let title: String
    let rows: [Row]
    var onOpen: ((Row) -> Void)? = nil

    private static let nameWidth: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 10)
            HStack(spacing: 0) {
                Text("Marqueur").frame(width: Self.nameWidth, alignment: .leading)
                Text("Statut")
                Spacer(minLength: 0)
                Text("Valeur")
            }
            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
            .foregroundStyle(SharpitColor.slate)
            .padding(.vertical, 6)
            .accessibilityHidden(true)
            ForEach(rows) { row in
                CliniqueDivider()
                if let onOpen {
                    Button { onOpen(row) } label: { line(row).contentShape(.rect) }
                        .buttonStyle(.sharpitPressable)
                        .accessibilityHint("Ouvre le détail")
                } else {
                    line(row)
                }
            }
        }
    }

    private func line(_ row: Row) -> some View {
        HStack(spacing: 0) {
            Text(row.name)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(2)
                .frame(width: Self.nameWidth, alignment: .leading)
            if let status = row.status {
                CliniqueStatusPill(status.word, status: status.status)
            }
            Spacer(minLength: SharpitSpacing.xs)
            Text(row.value)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

extension SanteTable.Row {
    /// A health marker: its norm's tone as the status, its value with its unit.
    init(_ marker: V1HealthMarker) {
        let value = SanteReadout.value(marker)
        let status = marker.norm.flatMap { SanteHeroReadout.status($0.tone) }
        self.init(
            id: marker.key.rawValue,
            name: SanteReadout.title(marker.key),
            status: status.map { (SanteHeroReadout.word($0), $0) },
            value: [value.text, value.unit].compactMap { $0 }.joined(separator: " ")
        )
    }

    /// A blood result: in the lab's interval or outside it; no pill without an interval.
    init(_ result: V1BloodTest.Result) {
        let status: (String, CliniqueStatus)? = switch result.status {
        case .inRange: (SanteHeroReadout.word(.good), .good)
        case .low, .high: (SanteHeroReadout.word(.watch), .watch)
        case .noReference: nil
        }
        self.init(
            id: result.markerKey,
            name: result.marker?.label ?? result.markerKey,
            status: status,
            value: BloodMarkerReadout.value(result.value, unit: result.unit)
        )
    }
}
