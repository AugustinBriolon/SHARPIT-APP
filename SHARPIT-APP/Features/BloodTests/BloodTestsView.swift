import Charts
import SwiftUI

// MARK: - History

/// Every blood test, latest first, then the markers measured more than once.
struct BloodTestsView: View {
    @State private var store: BloodTestsStore
    @State private var isImporting = false
    private let tokenProvider: () async throws -> String

    init(tokenProvider: @escaping () async throws -> String) {
        self.tokenProvider = tokenProvider
        _store = State(initialValue: BloodTestsStore(tokenProvider: tokenProvider))
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
        .background(SharpitCanvasBackground())
        .navigationTitle("Analyses de sang")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isImporting = true
                } label: {
                    Label("Importer une analyse", systemImage: "plus")
                }
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
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                if store.phase == .loaded, store.tests.isEmpty {
                    emptyState
                } else {
                    tests
                    followed
                }
                Text("Intervalles du laboratoire, pas un avis médical.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
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
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(String(localized: "Analyses"))
            SharpitInsetGroup {
                ForEach(store.tests) { test in
                    NavigationLink {
                        BloodTestDetailView(store: store, testId: test.id)
                    } label: {
                        BloodTestRow(test: test)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SharpitSpacing.cardPadding)
            .padding(.vertical, SharpitSpacing.xs)
            .sharpitSurface(.panel)
        }
    }

    @ViewBuilder
    private var followed: some View {
        let markers = store.followedMarkers
        if !markers.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow(String(localized: "Évolution"))
                SharpitInsetGroup {
                    ForEach(markers, id: \.markerKey) { history in
                        NavigationLink {
                            BloodMarkerHistoryView(history: history)
                        } label: {
                            BloodMarkerEvolutionRow(history: history)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SharpitSpacing.cardPadding)
                .padding(.vertical, SharpitSpacing.xs)
                .sharpitSurface(.panel)
            }
        }
    }
}

private struct BloodTestRow: View {
    let test: V1BloodTest

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.sampledAt.formatted(date: .long, time: .omitted))
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(summary)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(test.outOfRangeCount > 0 ? SharpitColor.signalCaution : SharpitColor.slate)
            }
            Spacer(minLength: SharpitSpacing.xs)
            Image(systemName: "chevron.right")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.xs)
        .frame(minHeight: SharpitSpacing.rowHeight)
        .contentShape(Rectangle())
    }

    private var summary: String {
        let count = String(localized: "\(test.results.count) marqueurs")
        guard test.outOfRangeCount > 0 else { return count }
        return String(localized: "\(count) · \(test.outOfRangeCount) hors intervalle")
    }
}

private struct BloodMarkerEvolutionRow: View {
    let history: BloodMarkerHistory

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Text(history.marker?.label ?? history.markerKey)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: SharpitSpacing.xs)
            if let latest = history.latest {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(BloodMarkerReadout.value(latest.value, unit: history.marker?.unit ?? ""))
                        .font(SharpitTypography.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(BloodMarkerReadout.isOutOfRange(latest.status) ? SharpitColor.signalCaution : SharpitColor.foreground)
                    if let change = history.lastChange {
                        Text(BloodMarkerReadout.delta(change))
                            .font(SharpitTypography.meta)
                            .monospacedDigit()
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
            }
            Image(systemName: "chevron.right")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.xs)
        .frame(minHeight: SharpitSpacing.rowHeight)
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
