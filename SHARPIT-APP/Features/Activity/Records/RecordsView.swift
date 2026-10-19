import Charts
import SwiftUI

/// Activité → Records: the best performances per sport, top five per category, as the web's
/// Progression › Performance lists them — then the best times over the reference distances for
/// running and, in the expert reading, the power curve for cycling (`docs/adr/0006`: the curve
/// is a technical reading, the records are not).
///
/// A record opens the session that set it, pushed in Activité's stack.
struct RecordsView: View {
    let store: RecordsStore
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    @State private var sport: RecordSport = .run
    @State private var openedActivityId: String?
    @Environment(\.isExpertReading) private var isExpertReading

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.top, SharpitSpacing.xs)
                .padding(.bottom, SharpitSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .background(SharpitCanvasBackground())
        .navigationTitle("Records")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $openedActivityId) { id in
            ActivityDetailView(activity: id, client: activityClient, tokenProvider: tokenProvider)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            RecordsLoading()
        case .loaded(let records):
            if records.isEmpty {
                ContentUnavailableView {
                    Label("Pas encore de record", systemImage: "trophy")
                } description: {
                    Text("Tes meilleures performances apparaîtront après tes premières séances synchronisées.")
                }
                .containerRelativeFrame(.vertical)
            } else {
                loaded(records)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Records indisponibles", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
            .containerRelativeFrame(.vertical)
        case .unauthorized:
            ContentUnavailableView {
                Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Reconnecte-toi pour recharger tes records.")
            }
            .containerRelativeFrame(.vertical)
        }
    }

    private func loaded(_ records: V1Records) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            Text(RecordsReadout.summary(records))
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.mutedForeground)

            SharpitSegmentedControl(
                selection: $sport,
                options: RecordSport.allCases.map {
                    SharpitSegmentedControl<RecordSport>.Option(value: $0, label: $0.label, symbol: $0.activityType.symbolName)
                }
            )

            VStack(spacing: SharpitSpacing.md) {
                ForEach(records.categories(for: sport)) { category in
                    RecordCategoryCard(category: category, sport: sport) { openedActivityId = $0 }
                }
            }
            .id(sport)
            .transition(.opacity)

            if sport == .run {
                let bests = records.runBests.filter { !$0.entries.isEmpty }
                if !bests.isEmpty {
                    RunBestsCard(bests: bests) { openedActivityId = $0 }
                }
            }

            if sport == .bike, isExpertReading, records.powerCurve.count > 1 {
                PowerCurveCard(points: records.powerCurve)
            }
        }
        .animation(SharpitMotion.selection, value: sport)
    }
}

// MARK: - Category

/// One record kind as the PR reference card: the best as the hero figure, « Nouveau record » while
/// it is fresh, the four behind it as rows in the grey group.
private struct RecordCategoryCard: View {
    let category: V1RecordCategory
    let sport: RecordSport
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(
                title: category.label,
                symbol: sport.activityType.symbolName,
                subtitle: category.entries.first.map { RecordsReadout.narrative($0.date) },
                showsChevron: false
            ) {
                if let best = category.entries.first, RecordsReadout.isRecent(best.date) {
                    SharpitPill(String(localized: "Nouveau PR"), style: .lime)
                }
            }

            if let best = category.entries.first {
                entryButton(best) { RecordHero(entry: best) }
                let others = Array(category.entries.dropFirst())
                if !others.isEmpty {
                    SharpitInsetGroup {
                        ForEach(others) { entry in
                            entryButton(entry) { RecordRow(entry: entry) }
                        }
                    }
                }
            } else {
                Text("—")
                    .font(SharpitTypography.data)
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.5))
                    .accessibilityLabel("Aucun record")
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    /// A record with its session opens it; one without (an import) only reads.
    @ViewBuilder
    private func entryButton<Content: View>(_ entry: V1RecordEntry, @ViewBuilder label: () -> Content) -> some View {
        let content = label()
        if let activityId = entry.activityId {
            Button { open(activityId) } label: { content }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Ouvrir la séance")
        } else {
            content
        }
    }
}

private struct RecordHero: View {
    let entry: V1RecordEntry

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                let figure = RecordsReadout.figure(entry.displayValue)
                SharpitHeroFigure(value: figure.value, unit: figure.unit)
                Text(RecordsReadout.meta(entry))
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: SharpitSpacing.xs)
            if entry.activityId != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordRow: View {
    let entry: V1RecordEntry

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            SharpitNumberChip(number: entry.rank)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayValue)
                    .font(SharpitTypography.system(size: 17, weight: .bold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                Text(RecordsReadout.meta(entry))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .subheadline, digits: true))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: SharpitSpacing.rowHeight, alignment: .leading)
        .sharpitSurface(.row)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Best times

/// The fastest time over each reference distance, from the recorded tracks.
private struct RunBestsCard: View {
    let bests: [V1RunBest]
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(
                title: String(localized: "Meilleurs temps"),
                symbol: "stopwatch",
                subtitle: String(localized: "Distances de référence"),
                showsChevron: false
            )
            SharpitInsetGroup {
                ForEach(bests) { best in
                    if let entry = best.entries.first {
                        if let activityId = entry.activityId {
                            Button { open(activityId) } label: { row(best, entry) }
                                .buttonStyle(.sharpitPressable)
                                .accessibilityHint("Ouvrir la séance")
                        } else {
                            row(best, entry)
                        }
                    }
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private func row(_ best: V1RunBest, _ entry: V1RecordEntry) -> some View {
        HStack(spacing: SharpitSpacing.sm) {
            Text(best.label)
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 72, alignment: .leading)
            if RecordsReadout.isRecent(entry.date) {
                SharpitPill("PR", style: .lime)
            }
            Spacer(minLength: SharpitSpacing.xs)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.displayValue)
                    .font(SharpitTypography.system(size: 20, weight: .bold, relativeTo: .title3, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                Text(RecordsReadout.meta(entry))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .subheadline, digits: true))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.xs)
        .frame(minHeight: SharpitSpacing.rowHeight)
        .sharpitSurface(.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Power curve

/// Best mean power per duration: the curve follows the finger, a notch per duration.
private struct PowerCurveCard: View {
    let points: [V1PowerCurvePoint]

    @State private var selectedLabel: String?

    private var selected: V1PowerCurvePoint? {
        selectedLabel.flatMap { label in points.first { $0.label == label } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(
                title: String(localized: "Courbe de puissance"),
                symbol: "bolt.fill",
                subtitle: String(localized: "Puissance moyenne maximale par durée"),
                showsChevron: false
            )

            chart

            if let selected {
                Text(scrubCaption(selected))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .onChange(of: selectedLabel) { _, label in
            if label != nil { SharpitHaptics.play(.notch(major: false)) }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value(String(localized: "Durée"), point.label), y: .value(String(localized: "Puissance"), point.watts))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(SharpitChartStyle.area)
                LineMark(x: .value(String(localized: "Durée"), point.label), y: .value(String(localized: "Puissance"), point.watts))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(SharpitChartStyle.line)
                    .lineStyle(StrokeStyle(lineWidth: SharpitChartStyle.lineWidth, lineCap: .round))
                PointMark(x: .value(String(localized: "Durée"), point.label), y: .value(String(localized: "Puissance"), point.watts))
                    .symbol { SharpitChartPoint() }
            }
            if let selected {
                RuleMark(x: .value(String(localized: "Durée"), selected.label))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value(String(localized: "Durée"), selected.label), y: .value(String(localized: "Puissance"), selected.watts))
                    .symbol { SharpitChartPoint() }
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SharpitChartBubble(text: RecordsReadout.watts(selected.watts))
                    }
            }
        }
        .chartXSelection(value: $selectedLabel)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: SharpitChartStyle.gridStroke).foregroundStyle(SharpitColor.analysisBorder)
                AxisValueLabel {
                    if let watts = value.as(Double.self) {
                        Text(RecordsReadout.watts(watts))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: SharpitChartStyle.gridStroke).foregroundStyle(SharpitColor.analysisBorder)
                AxisValueLabel()
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Courbe de puissance")
        .accessibilityValue(points.map { "\($0.label) \(RecordsReadout.watts($0.watts))" }.joined(separator: ", "))
    }

    /// « 20 min · 268 W · Sortie du dimanche · 3 mars 2026 »
    private func scrubCaption(_ point: V1PowerCurvePoint) -> String {
        let date = point.date.sharpitFormatted(.dateTime.day().month(.abbreviated).year())
        return [point.label, RecordsReadout.watts(point.watts), point.title, date]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct RecordsLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            RoundedRectangle(cornerRadius: 8)
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(width: 240, height: 28)
            RoundedRectangle(cornerRadius: 8)
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(height: 18)
            Capsule()
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(height: 40)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                    .fill(SharpitColor.analysisSurfaceAlt)
                    .frame(height: 150)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Chargement des records")
    }
}
