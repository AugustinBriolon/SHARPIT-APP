import Charts
import SwiftData
import SwiftUI

/// Réglages → Corps: where the body is today, as the scale measured it.
///
/// Read-only. A weigh-in is written by a scale, not typed, and the clinical annex a Withings
/// Body Scan records — vascular age, pulse wave velocity, nerve health — stays on the web,
/// which has the room to explain it.
struct BodyView: View {
    @State private var store: BodyCompositionStore

    init(
        client: any BodyCompositionServing,
        profileClient: (any AthleteProfileServing)? = nil,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        _store = State(
            initialValue: BodyCompositionStore(
                client: client,
                profileClient: profileClient,
                tokenProvider: tokenProvider,
                modelContext: modelContext
            )
        )
    }

    var body: some View {
        Group {
            switch store.phase {
            case .unauthorized:
                SharpitStateMessage.sessionExpired()
            case .failed(let message):
                SharpitStateMessage.failed(message) { Task { await store.load() } }
            case .empty:
                SharpitStateMessage(
                    title: "Aucune pesée",
                    symbol: "scalemass",
                    detail: "Connecte une balance sur le web, ou active Apple Santé dans Moi pour remonter les pesées de ta montre."
                )
            case .idle, .loading, .loaded:
                readout
            }
        }
        .navigationTitle("Corps")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.phase == .idle { await store.load() } }
    }

    /// Raised cards on the canvas, not a list: a weight and a trend line are readouts, and
    /// that is the case `docs/adr/0008` leaves custom.
    private var readout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                if store.phase == .loaded {
                    loaded
                } else {
                    BodySkeleton()
                }
            }
            .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var loaded: some View {
        if let latest = store.latest {
            weight(latest)
            composition(latest)
            history
        }
    }

    /// The one number Corps is about, and which way it has moved.
    private func weight(_ latest: V1BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Poids")
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text(ProfileFieldFormat.decimal(latest.weightKg).isEmpty
                     ? "—"
                     : ProfileFieldFormat.decimal(latest.weightKg))
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text("kg")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer(minLength: 0)
                if let trend = BodyTrend.weight(latest: latest, reference: store.reference) {
                    Text(trend.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(trend.tone)
                        .padding(.horizontal, SharpitSpacing.sm)
                        .padding(.vertical, SharpitSpacing.xxs + 2)
                        .background(trend.tone.opacity(0.14), in: Capsule())
                }
            }
            Text(measuredLine(latest))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    @ViewBuilder
    private func composition(_ latest: V1BodyMeasurement) -> some View {
        let tiles = BodyCompositionReadout.tiles(latest)
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow("Composition")
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: SharpitSpacing.sm),
                              GridItem(.flexible(), spacing: SharpitSpacing.sm)],
                    spacing: SharpitSpacing.sm
                ) {
                    ForEach(tiles) { tile in
                        SharpitStatTile(caption: tile.caption, value: tile.value, unit: tile.unit)
                    }
                }
                Text("Mesuré par ta balance. Une variation d'un jour à l'autre est de l'eau, pas de la composition.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Ninety days of weigh-ins as a line, not a list.
    ///
    /// A weight is a continuous measure read as a trend: a column of numbers makes the reader
    /// do the differencing, and the one thing they want to know — which way is this going —
    /// is the one thing a list does not say. Two points are not a trend, so the chart needs
    /// three.
    @ViewBuilder
    private var history: some View {
        let weighIns = store.weightSeries
        if weighIns.count > 2 {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow("\(BodyCompositionStore.windowDays) derniers jours")
                WeightTrendChart(points: weighIns, targetKg: store.targetWeightKg)
                Text("Chaque point est une pesée. La ligne suit la tendance, pas l'eau d'un matin.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func measuredLine(_ latest: V1BodyMeasurement) -> String {
        let day = latest.measuredAt.sharpitFormatted(.dateTime.day().month(.wide))
        guard let scale = BodyCompositionReadout.scaleLabel(latest.source) else { return day }
        return "\(day) · \(scale)"
    }
}

/// Corps, before the first byte: the same three shapes as `loaded`, redacted, so nothing
/// gets replaced with a bare spinner (`docs/adr/0008`).
private struct BodySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            weight
            composition
            chart
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    private var weight: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Poids")
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text("72,4")
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                Text("kg")
                    .font(SharpitTypography.meta)
                Spacer(minLength: 0)
            }
            Text("21 septembre")
                .font(SharpitTypography.meta)
        }
        .foregroundStyle(SharpitColor.mutedForeground)
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private var composition: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Composition")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: SharpitSpacing.sm),
                          GridItem(.flexible(), spacing: SharpitSpacing.sm)],
                spacing: SharpitSpacing.sm
            ) {
                SharpitStatTile(caption: "Masse grasse", value: "18,0", unit: "%")
                SharpitStatTile(caption: "Muscle", value: "41,0", unit: "%")
            }
        }
        .foregroundStyle(SharpitColor.mutedForeground)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("90 derniers jours")
            RoundedRectangle(cornerRadius: SharpitRadius.panel)
                .fill(SharpitColor.mutedForeground.opacity(0.12))
                .frame(height: 180)
        }
    }
}

/// The weight line, with the target drawn across it when the athlete set one.
private struct WeightTrendChart: View {
    let points: [BodyWeightPoint]
    let targetKg: Double?

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Jour", point.day),
                    y: .value("Poids", point.kilograms)
                )
                .foregroundStyle(SharpitColor.primary)
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Jour", point.day),
                    y: .value("Poids", point.kilograms)
                )
                .foregroundStyle(SharpitColor.primary)
                .symbolSize(points.count > 30 ? 8 : 24)
            }
            if let targetKg, targetKg > 0 {
                RuleMark(y: .value("Cible", targetKg))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("cible \(ProfileFieldFormat.decimal(targetKg)) kg")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
            }
        }
        // Never zero-based: a weight varies by a few percent, and a zeroed axis flattens
        // every real move into a straight line.
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                AxisValueLabel {
                    if let kilograms = value.as(Double.self) {
                        Text(ProfileFieldFormat.decimal(kilograms))
                    }
                }
            }
        }
        .frame(height: 180)
        .padding(SharpitSpacing.md)
        .sharpitSurface(.panel)
        .accessibilityLabel("Poids sur \(BodyCompositionStore.windowDays) jours")
        .accessibilityValue(accessibilitySummary)
    }

    /// A kilogram of padding either side, and the target inside the frame when there is one:
    /// a target drawn off-scale would be a line the athlete cannot place.
    private var domain: ClosedRange<Double> {
        let weights = points.map(\.kilograms)
        var low = (weights.min() ?? 0) - 1
        var high = (weights.max() ?? 1) + 1
        if let targetKg, targetKg > 0 {
            low = min(low, targetKg - 1)
            high = max(high, targetKg + 1)
        }
        return low...high
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else { return "" }
        return "de \(ProfileFieldFormat.decimal(first.kilograms)) à \(ProfileFieldFormat.decimal(last.kilograms)) kilogrammes"
    }
}
