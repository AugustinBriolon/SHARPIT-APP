import Charts
import SwiftUI

/// Activité → Records, as a board (the athlete's call, 2026-11-21): one section per sport on the
/// sheet, each kind of record a cell — its name, the best mark, and five bars for the five best,
/// so a record that stands alone is told from one the athlete keeps turning around. No tab per
/// sport, no card, no rank list: a cell opens its own page (`RecordDetailView`) for the five
/// marks, their dates and the session. Running's reference distances are a strip under its
/// cells; cycling's power curve, in the expert reading only (`docs/adr/0006`), a line under its.
struct RecordsView: View {
    let store: RecordsStore
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    @State private var focus: RecordFocus?
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
        .cliniqueSheet(wash: .neutral, height: 240)
        .navigationTitle("Records")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $focus) { focus in
            RecordDetailView(focus: focus, store: store, activityClient: activityClient, tokenProvider: tokenProvider)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            // The board itself, redacted over placeholder marks.
            board(RecordsReadout.placeholder)
                .redacted(reason: .placeholder)
                .disabled(true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chargement des records")
        case .loaded(let records):
            if records.isEmpty {
                ContentUnavailableView {
                    Label("Pas encore de record", systemImage: "trophy")
                } description: {
                    Text("Tes meilleures performances apparaîtront après tes premières séances synchronisées.")
                }
                .containerRelativeFrame(.vertical)
            } else {
                board(records)
            }
        case .failed(let message):
            SharpitStateMessage.failed(message) { Task { await store.load() } }
                .embedded()
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

    private func board(_ records: V1Records) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xl) {
            ForEach(RecordSport.allCases) { sport in
                let categories = records.categories(for: sport)
                let bests = sport == .run ? records.runBests.filter { !$0.entries.isEmpty } : []
                let showsCurve = sport == .bike && isExpertReading && records.powerCurve.count > 1
                if categories.contains(where: { !$0.entries.isEmpty }) || !bests.isEmpty || showsCurve {
                    RecordSportSection(
                        sport: sport, categories: categories, bests: bests, showsCurve: showsCurve
                    ) { focus = $0 }
                }
            }
        }
    }
}

/// What a tap on the board opens.
enum RecordFocus: Hashable, Identifiable {
    case category(RecordSport, key: String)
    case runBest(meters: Int)
    case powerCurve

    var id: Self { self }
}

// MARK: - Sport section

/// One sport on the sheet: its glyph and name, its records as cells split by hairlines, then
/// what only that sport has.
private struct RecordSportSection: View {
    let sport: RecordSport
    let categories: [V1RecordCategory]
    let bests: [V1RunBest]
    let showsCurve: Bool
    let open: (RecordFocus) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Two cells a row; one at the accessibility sizes, where a figure needs the width.
    private var rows: [[V1RecordCategory]] {
        let width = typeSize.isAccessibilitySize ? 1 : 2
        return stride(from: 0, to: categories.count, by: width).map {
            Array(categories[$0..<min($0 + width, categories.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SharpitSpacing.sm) {
                CliniqueSportTile(symbol: sport.activityType.symbolName, size: 36)
                Text(sport.label)
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, SharpitSpacing.sm)

            CliniqueDivider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { index, category in
                        if index > 0 {
                            Rectangle()
                                .fill(SharpitColor.divider)
                                .frame(width: 1)
                                .padding(.trailing, SharpitSpacing.md)
                                .accessibilityHidden(true)
                        }
                        RecordCell(category: category) { open(.category(sport, key: category.key)) }
                            .padding(.trailing, index == 0 && row.count > 1 ? SharpitSpacing.md : 0)
                    }
                    // An odd last cell keeps its half, so the figures stay in two columns.
                    if row.count == 1, !typeSize.isAccessibilitySize {
                        Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                CliniqueDivider()
            }

            if !bests.isEmpty {
                RunBestsStrip(bests: bests) { open(.runBest(meters: $0)) }
                CliniqueDivider()
            }

            if showsCurve {
                Button { open(.powerCurve) } label: {
                    HStack {
                        Text("Courbe de puissance")
                            .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                            .foregroundStyle(SharpitColor.foreground)
                        Spacer(minLength: SharpitSpacing.xs)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SharpitColor.slate.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: SharpitSpacing.rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                CliniqueDivider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One kind of record: its name, the best mark, the five best as bars. A fresh record carries a dot.
private struct RecordCell: View {
    let category: V1RecordCategory
    let open: () -> Void

    var body: some View {
        if let best = category.entries.first {
            Button(action: open) { label(best) }
                .buttonStyle(.sharpitPressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(category.label), \(best.displayValue), \(RecordsReadout.narrative(best.date))")
                .accessibilityAddTraits(.isButton)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                name(isRecent: false)
                Text("—")
                    .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2, digits: true))
                    .foregroundStyle(SharpitColor.slate.opacity(0.5))
            }
            .padding(.vertical, SharpitSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(category.label), aucun record")
        }
    }

    private func label(_ best: V1RecordEntry) -> some View {
        let figure = RecordsReadout.figure(best.displayValue)
        return VStack(alignment: .leading, spacing: 6) {
            name(isRecent: RecordsReadout.isRecent(best.date))
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: SharpitSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(figure.value)
                        .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2, digits: true))
                        .tracking(-0.5)
                        .foregroundStyle(SharpitColor.foreground)
                    if let unit = figure.unit {
                        Text(unit)
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                RecordBars(fractions: RecordsReadout.fractions(category.entries))
            }
        }
        .padding(.vertical, SharpitSpacing.sm)
        // As tall as its neighbour, so two figures share a baseline when one name wraps.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func name(isRecent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(category.label)
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if isRecent {
                Circle()
                    .fill(CliniqueStatus.good.mark)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The five best marks as bars against the record: the record in ink, the others behind it.
struct RecordBars: View {
    let fractions: [Double]
    var height: CGFloat = 26

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index == 0 ? SharpitColor.foreground : SharpitColor.outline)
                    .frame(width: 5, height: max(3, height * fraction))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// The best time over each reference distance, as columns between two hairlines. They scroll
/// sideways when the tracks cover more distances than the width holds.
private struct RunBestsStrip: View {
    let bests: [V1RunBest]
    let open: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(bests.enumerated()), id: \.element.id) { index, best in
                    if index > 0 {
                        Rectangle()
                            .fill(SharpitColor.divider)
                            .frame(width: 1, height: 32)
                            .accessibilityHidden(true)
                    }
                    if let entry = best.entries.first {
                        Button { open(best.meters) } label: {
                            VStack(spacing: 2) {
                                Text(best.label)
                                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                                    .foregroundStyle(SharpitColor.slate)
                                Text(entry.displayValue)
                                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                                    .foregroundStyle(SharpitColor.foreground)
                            }
                            .lineLimit(1)
                            .frame(minWidth: 96, minHeight: SharpitSpacing.minimumTouchTarget)
                            .padding(.vertical, SharpitSpacing.sm)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.sharpitPressable)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Detail

/// One record's page: the best mark read big, its session, the five best as bars with their
/// dates, and those five placed in time. The power curve takes the same page.
struct RecordDetailView: View {
    let focus: RecordFocus
    let store: RecordsStore
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    @State private var openedActivityId: String?

    /// What the page reads, looked up in the store so a refresh behind it shows.
    private var subject: (eyebrow: String, entries: [V1RecordEntry])? {
        guard let records = store.records else { return nil }
        switch focus {
        case .category(let sport, let key):
            guard let category = records.categories(for: sport).first(where: { $0.key == key }) else { return nil }
            return ("\(sport.label) · \(category.label)", category.entries)
        case .runBest(let meters):
            guard let best = records.runBests.first(where: { $0.meters == meters }) else { return nil }
            return ("\(RecordSport.run.label) · \(best.label)", best.entries)
        case .powerCurve:
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.xl) {
                if focus == .powerCurve, let points = store.records?.powerCurve, points.count > 1 {
                    PowerCurveCard(points: points)
                } else if let subject, let best = subject.entries.first {
                    hero(subject.eyebrow, best)
                    ranks(subject.entries)
                    if subject.entries.count > 1 {
                        RecordTimeline(entries: subject.entries)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, SharpitSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .cliniqueSheet(wash: .neutral, height: 240)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedActivityId) { id in
            ActivityDetailView(activity: id, client: activityClient, tokenProvider: tokenProvider)
        }
    }

    private func hero(_ eyebrow: String, _ best: V1RecordEntry) -> some View {
        let figure = RecordsReadout.figure(best.displayValue)
        return VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text(eyebrow)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .accessibilityAddTraits(.isHeader)
            SharpitHeroFigure(value: figure.value, unit: figure.unit)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: SharpitSpacing.xs) {
                if RecordsReadout.isRecent(best.date) {
                    CliniqueStatusPill(String(localized: "Nouveau"), status: .good)
                }
                Text(RecordsReadout.meta(best))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .subheadline, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
            }
            if let activityId = best.activityId {
                Button { openedActivityId = activityId } label: {
                    Text("Voir la séance").frame(maxWidth: .infinity)
                }
                .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                .padding(.top, SharpitSpacing.sm)
            }
        }
    }

    private func ranks(_ entries: [V1RecordEntry]) -> some View {
        let fractions = RecordsReadout.fractions(entries)
        return VStack(alignment: .leading, spacing: 0) {
            Text(entries.count == 1 ? String(localized: "Ta meilleure marque") : String(localized: "Tes \(entries.count) meilleures"))
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, SharpitSpacing.sm)
            CliniqueDivider()
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                rankRow(entry, fraction: index < fractions.count ? fractions[index] : 0)
                CliniqueDivider()
            }
        }
    }

    /// A rank with its session opens it; one without (an import) only reads.
    @ViewBuilder
    private func rankRow(_ entry: V1RecordEntry, fraction: Double) -> some View {
        let row = HStack(spacing: SharpitSpacing.sm) {
            Text("\(entry.rank)")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline, digits: true))
                .foregroundStyle(SharpitColor.slate)
                .frame(width: 14, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(entry.rank == 1 ? SharpitColor.foreground : SharpitColor.outline)
                    .frame(width: max(8, proxy.size.width * fraction), height: 8)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .accessibilityHidden(true)
            Text(entry.displayValue)
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)
                .fixedSize()
            Text(entry.date.sharpitFormatted(.dateTime.day().month(.abbreviated).year()))
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: SharpitSpacing.minimumTouchTarget)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)

        if let activityId = entry.activityId {
            Button { openedActivityId = activityId } label: { row }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Ouvrir la séance")
        } else {
            row
        }
    }
}

/// The best marks placed by date. Only the five the server keeps: it reads when they were set,
/// not the whole history, and its title says no more than that.
private struct RecordTimeline: View {
    let entries: [V1RecordEntry]

    private var byDate: [V1RecordEntry] { entries.sorted { $0.date < $1.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("Dans le temps")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Chart {
                ForEach(byDate, id: \.rank) { entry in
                    LineMark(x: .value(String(localized: "Date"), entry.date), y: .value(String(localized: "Marque"), entry.value))
                        .foregroundStyle(SharpitChartStyle.line)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    PointMark(x: .value(String(localized: "Date"), entry.date), y: .value(String(localized: "Marque"), entry.value))
                        .symbolSize(entry.rank == 1 ? 110 : 50)
                        .foregroundStyle(entry.rank == 1 ? SharpitColor.foreground : SharpitColor.slate)
                }
            }
            // A pace or a time is better lower: the axis turns so better is always up.
            .chartYScale(domain: .automatic(includesZero: false, reversed: RecordsReadout.lowerIsBetter(entries)))
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: SharpitChartStyle.gridStroke).foregroundStyle(SharpitColor.divider)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year().locale(SharpitLocale.current))
                }
            }
            .frame(height: 140)
            .accessibilityLabel("Tes meilleures marques dans le temps")
            .accessibilityValue(byDate.map { "\($0.date.sharpitFormatted(.dateTime.day().month(.abbreviated).year())) \($0.displayValue)" }.joined(separator: ", "))
        }
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
                showsChevron: false
            )

            chart

            if let selected {
                Text(scrubCaption(selected))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(SharpitColor.slate.opacity(0.5))
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
                AxisGridLine(stroke: SharpitChartStyle.gridStroke).foregroundStyle(SharpitColor.divider)
                AxisValueLabel {
                    if let watts = value.as(Double.self) {
                        Text(RecordsReadout.watts(watts))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: SharpitChartStyle.gridStroke).foregroundStyle(SharpitColor.divider)
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

