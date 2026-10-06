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
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text("Meilleures performances")
                    .font(SharpitTypography.pageTitle)
                    .tracking(SharpitTypography.pageTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text(RecordsReadout.summary(records))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            SharpitSegmentedControl(
                selection: $sport,
                options: RecordSport.allCases.map {
                    SharpitSegmentedControl<RecordSport>.Option(value: $0, label: $0.label, symbol: $0.activityType.symbolName)
                }
            )

            VStack(spacing: SharpitSpacing.sm) {
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

/// One record kind: the best on its own line, the four behind it under a rule.
private struct RecordCategoryCard: View {
    let category: V1RecordCategory
    let sport: RecordSport
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(
                title: category.label,
                symbol: sport.activityType.symbolName,
                tint: SharpitSportTone.label(for: sport.activityType),
                showsChevron: false
            )

            if let best = category.entries.first {
                entryButton(best) { RecordHero(entry: best) }
                let others = Array(category.entries.dropFirst())
                if !others.isEmpty {
                    Divider()
                    VStack(spacing: 0) {
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
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text(entry.displayValue)
                    .font(SharpitTypography.gaugeScore)
                    .tracking(SharpitTypography.gaugeScoreTracking)
                    .foregroundStyle(SharpitColor.recordAccent)
                    .monospacedDigit()
                Text(RecordsReadout.meta(entry))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
                Text(RecordsReadout.narrative(entry.date))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: SharpitSpacing.xs)
            VStack(alignment: .trailing, spacing: SharpitSpacing.xs) {
                if RecordsReadout.isRecent(entry.date) {
                    SharpitInlineTag("Nouveau")
                }
                if entry.activityId != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                        .accessibilityHidden(true)
                }
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
            Text("#\(entry.rank)")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .monospacedDigit()
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayValue)
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.foreground)
                    .monospacedDigit()
                Text(RecordsReadout.meta(entry))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: SharpitSpacing.xs)
            Text(RecordsReadout.narrative(entry.date))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
        }
        .padding(.vertical, SharpitSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(
                title: "Meilleurs temps",
                symbol: "stopwatch",
                tint: SharpitSportTone.label(for: .run),
                showsChevron: false
            )
            VStack(spacing: 0) {
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
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayValue)
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.foreground)
                    .monospacedDigit()
                Text(RecordsReadout.meta(entry))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: SharpitSpacing.xs)
            if RecordsReadout.isRecent(entry.date) {
                SharpitInlineTag("Nouveau")
            }
        }
        .padding(.vertical, SharpitSpacing.xs)
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
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(
                title: "Courbe de puissance",
                symbol: "bolt",
                tint: SharpitSportTone.label(for: .bike),
                showsChevron: false
            )
            Text("Puissance maximale moyenne soutenue par durée.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)

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
                LineMark(x: .value("Durée", point.label), y: .value("Puissance", point.watts))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(SharpitColor.recordAccent)
                PointMark(x: .value("Durée", point.label), y: .value("Puissance", point.watts))
                    .foregroundStyle(SharpitColor.recordAccent)
                    .symbolSize(22)
            }
            if let selected {
                RuleMark(x: .value("Durée", selected.label))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Durée", selected.label), y: .value("Puissance", selected.watts))
                    .foregroundStyle(SharpitColor.recordAccent)
                    .symbolSize(90)
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text(RecordsReadout.watts(selected.watts))
                            .font(SharpitTypography.instrument)
                            .monospacedDigit()
                            .foregroundStyle(SharpitColor.foreground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SharpitElevatedColor.panelOnSheet, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
                            .sharpitShadow(.control)
                    }
            }
        }
        .chartXSelection(value: $selectedLabel)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                AxisValueLabel {
                    if let watts = value.as(Double.self) {
                        Text(RecordsReadout.watts(watts))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
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
