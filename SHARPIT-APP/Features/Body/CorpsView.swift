import Charts
import SwiftData
import SwiftUI

/// The Corps tab: what SHARPIT knows of the athlete's body, as a readout.
///
/// Weight first, then recovery, composition and thresholds — the causal column's state and
/// evidence. Every value is a tile that opens its drawer, where the trend lives; a metric with
/// no data is absent, never an empty tile. Thresholds are edited from their section, which
/// replaces Moi → Seuils & repères.
struct CorpsView: View {
    @State private var store: CorpsStore
    private let profileClient: any AthleteProfileServing
    private let tokenProvider: () async throws -> String
    private let modelContext: ModelContext?

    @State private var opened: CorpsMetric?
    @State private var isEditingThresholds = false
    @State private var isEditingWeightTarget = false
    @State private var hasAppeared = false

    init(
        profileClient: any AthleteProfileServing & BodyCompositionServing,
        recoveryClient: any RecoveryServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        self.profileClient = profileClient
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
        _store = State(initialValue: CorpsStore(
            profileClient: profileClient,
            bodyClient: profileClient,
            recoveryClient: recoveryClient,
            tokenProvider: tokenProvider
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .unauthorized:
                    SharpitStateMessage.sessionExpired()
                case .failed(let message):
                    SharpitStateMessage.failed(message) { Task { await store.load() } }
                case .empty:
                    SharpitStateMessage(
                        title: "Rien de mesuré pour l'instant",
                        symbol: "figure.stand",
                        detail: "Connecte Garmin ou une balance dans Paramètres → Sources de données : tes mesures apparaîtront ici."
                    )
                case .loading, .loaded:
                    readout
                }
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Corps")
            .navigationBarTitleDisplayMode(.large)
            .modifier(LiquidNavChrome())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isEditingWeightTarget = true
                    } label: {
                        Label("Objectif de poids", systemImage: "target")
                    }
                }
            }
            .sheet(isPresented: $isEditingWeightTarget, onDismiss: { Task { await store.load() } }) {
                WeightTargetSheet(profileClient: profileClient, tokenProvider: tokenProvider)
            }
            .task { await store.load() }
            .sheet(item: $opened) { metric in
                CorpsMetricDrawer(
                    metric: metric,
                    target: metric.key == .weight ? store.targetWeightKg : nil
                ) { range in
                    await store.series(for: metric, range: range)
                }
            }
            .sheet(isPresented: $isEditingThresholds, onDismiss: { Task { await store.load() } }) {
                NavigationStack {
                    ThresholdsView(client: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("OK") { isEditingThresholds = false }
                            }
                        }
                }
                .sharpitSheet()
            }
        }
    }

    private var readout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                if store.phase == .loaded {
                    if let weight = store.metric(.weight) {
                        CorpsHeroTile(metric: weight, targetKg: store.targetWeightKg) { opened = weight }
                            .revealed(hasAppeared, index: 0)
                    }
                    section(.recovery, index: 1)
                    section(.composition, index: 2)
                    section(.thresholds, index: 3) { isEditingThresholds = true }
                } else {
                    CorpsSkeleton()
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.xl)
        }
        .modifier(ScrollUnderGlass())
        .refreshable { await store.load() }
        .onAppear { hasAppeared = true }
    }

    @ViewBuilder
    private func section(
        _ section: CorpsSection,
        index: Int,
        onEdit: (() -> Void)? = nil
    ) -> some View {
        let metrics = store.metrics(in: section)
        if !metrics.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    SharpitEyebrow(section.title)
                    Spacer(minLength: 0)
                    if let onEdit {
                        Button("Modifier", action: onEdit)
                            .font(SharpitTypography.meta.weight(.semibold))
                            .foregroundStyle(SharpitColor.primary)
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: SharpitSpacing.sm),
                              GridItem(.flexible(), spacing: SharpitSpacing.sm)],
                    spacing: SharpitSpacing.sm
                ) {
                    ForEach(metrics) { metric in
                        CorpsMetricTile(metric: metric) { opened = metric }
                    }
                }
            }
            .revealed(hasAppeared, index: index)
        }
    }
}

// MARK: - Tiles

extension CorpsTone {
    var color: Color {
        switch self {
        case .neutral: SharpitColor.mutedForeground
        case .inRange: SharpitColor.signalRecovery
        case .belowRange: SharpitColor.signalCaution
        }
    }
}

/// The weight, large, with its change and a line of the last weeks.
private struct CorpsHeroTile: View {
    let metric: CorpsMetric
    let targetKg: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                HStack {
                    SharpitEyebrow(metric.key.label)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .lastTextBaseline, spacing: SharpitSpacing.xs) {
                    Text(metric.formattedValue)
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.numericText(value: metric.value))
                    if let unit = metric.key.unit {
                        Text(unit)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    Spacer(minLength: SharpitSpacing.sm)
                    CorpsSparkline(points: Array(metric.series.suffix(30)), tone: SharpitColor.primary)
                        .frame(width: 110, height: 40)
                }
                HStack(spacing: SharpitSpacing.xs) {
                    if let note = metric.note {
                        Text(note)
                            .font(SharpitTypography.meta.weight(.semibold))
                            .foregroundStyle(SharpitColor.foreground)
                    }
                    Text(CorpsFormat.caption(metric))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Spacer(minLength: 0)
                    if let targetKg, targetKg > 0 {
                        Label("cible \(ProfileFieldFormat.decimal(targetKg)) kg", systemImage: "target")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre l'évolution")
    }
}

/// One metric: its value, a short reading and a small trend, opening the drawer.
private struct CorpsMetricTile: View {
    let metric: CorpsMetric
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                HStack(alignment: .top) {
                    Text(metric.key.label)
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .lastTextBaseline, spacing: SharpitSpacing.xxs) {
                    Text(metric.formattedValue)
                        .font(SharpitTypography.data)
                        .tracking(SharpitTypography.dataTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.numericText(value: metric.value))
                    if let unit = metric.key.unit {
                        Text(unit)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                HStack(alignment: .bottom, spacing: SharpitSpacing.xs) {
                    Text(metric.note ?? " ")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(metric.tone.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    if metric.series.count > 2 {
                        CorpsSparkline(points: Array(metric.series.suffix(20)), tone: SharpitColor.primary)
                            .frame(width: 44, height: 18)
                    }
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre l'évolution")
    }
}

/// A trend at a glance: no axes, no labels — the drawer carries those.
private struct CorpsSparkline: View {
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
                    Text(metric.key.explanation)
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

/// Corps before the first byte: a hero and two groups of tiles, redacted (`docs/adr/0008`).
private struct CorpsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            RoundedRectangle(cornerRadius: SharpitRadius.panel)
                .fill(SharpitColor.mutedForeground.opacity(0.12))
                .frame(height: 132)
            ForEach(0..<2, id: \.self) { _ in
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: SharpitSpacing.sm
                ) {
                    ForEach(0..<4, id: \.self) { _ in
                        SharpitStatTile(caption: "Mesure", value: "00,0", unit: "kg")
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
