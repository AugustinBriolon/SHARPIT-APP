import Charts
import SwiftUI

// MARK: - History

/// Every blood test, latest first, then the markers measured more than once.
struct BloodTestsView: View {
    @State private var store: BloodTestsStore
    @State private var isImporting = false
    /// The marker « Évolution » draws; the first followed one until the athlete picks.
    @State private var shownMarker: String?
    private let tokenProvider: () async throws -> String

    init(client: any BloodTestServing = BloodTestClient(), tokenProvider: @escaping () async throws -> String) {
        self.tokenProvider = tokenProvider
        _store = State(initialValue: BloodTestsStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        Group {
            switch store.phase {
            case .unauthorized:
                SharpitStateMessage.sessionExpired()
            case .failed(let message):
                SharpitStateMessage.failed(message) { Task { await store.load() } }
            case .loading, .loaded:
                content
            }
        }
        .cliniqueSheet(wash: store.tests.first.map { $0.outOfRangeCount > 0 } == true ? .watch : .neutral, height: 240)
        .navigationTitle("Analyses de sang")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Importer") { isImporting = true }
                    .accessibilityLabel("Importer une analyse")
            }
        }
        .navigationDestination(isPresented: $isImporting) {
            BloodTestImportView(tokenProvider: tokenProvider)
        }
        // On first show and on the way back from an import.
        .onAppear { Task { await store.load() } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Intervalles du laboratoire, pas un avis médical.")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .padding(.top, -12)
                if store.phase == .loaded, store.tests.isEmpty {
                    emptyState
                } else {
                    followed
                    tests
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, SharpitSpacing.md)
        }
        .refreshable { await store.load() }
        .redacted(reason: store.phase == .loading ? .placeholder : [])
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(title: String(localized: "Aucune analyse"), symbol: "drop", showsChevron: false)
            Text("Importe le PDF de ton laboratoire : seules les valeurs sont gardées, jamais le document.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
            SharpitPrimaryButton(title: String(localized: "Importer un compte rendu")) { isImporting = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tests: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHead(String(localized: "Analyses"), trailing: BloodTestsReadout.count(store.tests.count))
            ForEach(Array(store.tests.enumerated()), id: \.element.id) { index, test in
                if index > 0 { CliniqueDivider() }
                NavigationLink {
                    BloodTestDetailView(store: store, testId: test.id)
                } label: {
                    BloodTestRow(test: test)
                }
                .buttonStyle(.sharpitPressable)
            }
        }
    }

    private func sectionHead(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SharpitTypography.system(size: 20, weight: .semibold, relativeTo: .title3))
                .tracking(-0.3)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: SharpitSpacing.xs)
            if let trailing {
                Text(trailing)
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
        }
    }

    /// « Évolution »: one marker measured twice or more as a curve over its lab interval, the
    /// others a chip away; the curve opens the marker's own page.
    @ViewBuilder
    private var followed: some View {
        let markers = store.followedMarkers
        if let shown = markers.first(where: { $0.markerKey == shownMarker }) ?? markers.first {
            VStack(alignment: .leading, spacing: 10) {
                sectionHead(
                    String(localized: "Évolution"),
                    trailing: [shown.marker?.label ?? shown.markerKey, shown.marker?.unit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                )
                NavigationLink {
                    BloodMarkerHistoryView(history: shown)
                } label: {
                    BloodEvolutionChart(history: shown)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Ouvre toutes les valeurs")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(markers, id: \.markerKey) { history in
                            let isChosen = history.markerKey == shown.markerKey
                            Button { shownMarker = history.markerKey } label: {
                                Text(history.marker?.label ?? history.markerKey)
                                    .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                                    .foregroundStyle(isChosen ? SharpitColor.primaryForeground : SharpitColor.foreground)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 34)
                                    .background(isChosen ? SharpitColor.primary : .clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(SharpitColor.outline, lineWidth: isChosen ? 0 : 1))
                            }
                            .buttonStyle(.sharpitPressable)
                            .accessibilityAddTraits(isChosen ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }
}

enum BloodTestsReadout {
    /// « 4 comptes rendus »
    static func count(_ count: Int) -> String {
        count == 1 ? String(localized: "1 compte rendu") : String(localized: "\(count) comptes rendus")
    }
}

/// A marker across the tests that measured it: a line over its area, in the watch hue when the
/// latest value sits outside the lab's interval, the interval's nearest bound dashed.
private struct BloodEvolutionChart: View {
    let history: BloodMarkerHistory

    var body: some View {
        let isOut = history.latest.map { BloodMarkerReadout.isOutOfRange($0.status) } ?? false
        let tone = isOut ? SharpitColor.statusWatchMark : SharpitColor.pillarSleep
        let values = history.points.map(\.value) + [history.latest?.refLow, history.latest?.refHigh].compactMap { $0 }
        let domain = CorpsFormat.domain(values, padding: 0.15)
        Chart {
            ForEach(history.points) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Bas", domain.lowerBound), yEnd: .value("Valeur", point.value))
                    .foregroundStyle(tone.opacity(0.12))
                LineMark(x: .value("Date", point.date), y: .value("Valeur", point.value))
                    .foregroundStyle(tone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach([history.latest?.refLow, history.latest?.refHigh].compactMap { $0 }, id: \.self) { bound in
                RuleMark(y: .value("Intervalle", bound))
                    .foregroundStyle(SharpitColor.outline)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .frame(height: 84)
        .contentShape(.rect)
        .accessibilityLabel("Évolution de \(history.marker?.label ?? history.markerKey)")
    }
}

private struct BloodTestRow: View {
    let test: V1BloodTest

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.sampledAt.sharpitFormatted(.dateTime.day().month(.wide).year()))
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                Text(test.results.count == 1 ? String(localized: "1 marqueur") : String(localized: "\(test.results.count) marqueurs"))
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
            Spacer(minLength: SharpitSpacing.xs)
            CliniqueStatusPill(
                test.outOfRangeCount > 0 ? String(localized: "\(test.outOfRangeCount) à surveiller") : String(localized: "Tout dans la plage"),
                status: test.outOfRangeCount > 0 ? .watch : .good
            )
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SharpitColor.slate.opacity(0.6))
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }
}

// MARK: - One test

/// One test as a clean table: each marker, where it sits in the lab's interval, its value.
struct BloodTestDetailView: View {
    let store: BloodTestsStore
    let testId: String
    @State private var isConfirmingDelete = false
    @State private var reading: BloodTestReadingStore?
    /// The marker whose history is pushed.
    @State private var openedMarker: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let test = store.test(testId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header(test)
                        SanteTable(
                            title: SanteReadout.biomarkers(test.results.count),
                            rows: test.results.map(SanteTable.Row.init),
                            onOpen: { openedMarker = $0.id }
                        )
                        if let reading {
                            BloodTestReadingCard(store: reading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, SharpitSpacing.xs)
                    .padding(.bottom, SharpitSpacing.xl)
                }
                .cliniqueSheet(wash: test.outOfRangeCount > 0 ? .watch : .good, height: 240)
                .navigationTitle(test.sampledAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // The page names itself; the bar keeps the way back and the deletion.
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isConfirmingDelete = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Supprimer l'analyse")
            }
        }
        .navigationDestination(item: $openedMarker) { key in
            BloodMarkerHistoryView(history: store.history(of: key))
        }
        .confirmationDialog("Supprimer cette analyse ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                dismiss()
                Task { await store.delete(testId) }
            }
        } message: {
            Text("Ses valeurs sont effacées de SHARPIT. Tu pourras réimporter le compte rendu.")
        }
        .task {
            let store = store.makeReadingStore()
            reading = store
            await store.load(testId: testId)
        }
    }

    /// How many values deserve a look as a pill, the test and its day, how many sit in the lab's range.
    private func header(_ test: V1BloodTest) -> some View {
        VStack(spacing: 10) {
            CliniqueStatusPill(
                test.outOfRangeCount > 0 ? String(localized: "\(test.outOfRangeCount) à regarder") : String(localized: "Tout dans la plage"),
                status: test.outOfRangeCount > 0 ? .watch : .good
            )
            Image(systemName: "doc.text")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(SharpitColor.slate)
                .padding(.vertical, 6)
                .accessibilityHidden(true)
            Text("Analyse sanguine, \(test.sampledAt.sharpitFormatted(.dateTime.day().month(.abbreviated).year()))")
                .font(SharpitTypography.system(size: 22, weight: .semibold, relativeTo: .title2, digits: true))
                .tracking(-0.3)
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("\(test.results.count - test.outOfRangeCount) sur \(test.results.count) dans la plage du laboratoire")
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                .foregroundStyle(SharpitColor.slate)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - One marker

/// A marker across the tests: its curve over the lab's latest interval, then every value.
struct BloodMarkerHistoryView: View {
    let history: BloodMarkerHistory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                if history.points.count > 1 {
                    chart
                }
                values
                Text("Une variation entre deux analyses peut venir du laboratoire, de l'heure ou de l'entraînement de la veille.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(history.marker?.label ?? history.markerKey)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chart: some View {
        Chart {
            if let latest = history.latest, latest.refLow != nil || latest.refHigh != nil {
                RectangleMark(
                    yStart: .value("Bas", latest.refLow ?? domain.lowerBound),
                    yEnd: .value("Haut", latest.refHigh ?? domain.upperBound)
                )
                .foregroundStyle(SharpitColor.statusGoodMark.opacity(0.12))
            }
            ForEach(history.points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Valeur", point.value))
                    .foregroundStyle(SharpitChartStyle.line)
                    .lineStyle(StrokeStyle(lineWidth: SharpitChartStyle.lineWidth, lineCap: .round))
                PointMark(x: .value("Date", point.date), y: .value("Valeur", point.value))
                    .symbol { SharpitChartPoint() }
            }
        }
        .chartYScale(domain: domain)
        .sharpitChartAxes()
        .frame(height: 200)
        .accessibilityLabel("Courbe de \(history.marker?.label ?? history.markerKey)")
    }

    /// Values and the interval, with air above and below so neither touches an edge.
    private var domain: ClosedRange<Double> {
        let bounds = history.points.flatMap { [$0.value, $0.refLow, $0.refHigh].compactMap { $0 } }
        let low = bounds.min() ?? 0, high = bounds.max() ?? 1
        let pad = max((high - low) * 0.15, abs(high) * 0.05, 0.01)
        return (low - pad)...(high + pad)
    }

    private var values: some View {
        SharpitInsetGroup {
            ForEach(history.points.reversed()) { point in
                HStack(spacing: SharpitSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.date.formatted(date: .long, time: .omitted))
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Text(BloodMarkerReadout.caption(status: point.status, low: point.refLow, high: point.refHigh))
                            .font(SharpitTypography.meta)
                            .foregroundStyle(BloodMarkerReadout.isOutOfRange(point.status) ? SharpitColor.signalCaution : SharpitColor.slate)
                    }
                    Spacer(minLength: SharpitSpacing.xs)
                    Text(BloodMarkerReadout.value(point.value, unit: history.marker?.unit ?? ""))
                        .font(SharpitTypography.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                }
                .padding(.horizontal, SharpitSpacing.rowPaddingX)
                .padding(.vertical, SharpitSpacing.xs)
                .frame(minHeight: SharpitSpacing.rowHeight)
            }
        }
        .padding(.horizontal, SharpitSpacing.cardPadding)
        .padding(.vertical, SharpitSpacing.xs)
        .sharpitSurface(.panel)
    }
}
