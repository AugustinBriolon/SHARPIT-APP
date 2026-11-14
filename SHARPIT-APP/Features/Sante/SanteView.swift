import SwiftData
import SwiftUI

/// The Santé tab: the athlete's health as a check-up (SHARPIT ADR-053).
///
/// Ranked by what matters most: the month's synthesis, what deserves attention now, the four
/// vital signs, then body composition, then the daily context. Every marker is read against a
/// published norm and against the athlete's own month — both the web's — and opens its sheet,
/// where the source of its norm and its longer history live. Training thresholds are not health:
/// they live in Paramètres › Seuils d'entraînement.
struct SanteView: View {
    @Environment(ProStore.self) private var pro: ProStore?
    @State private var store: SanteStore
    /// The Corps reads: the longer histories behind a marker's sheet, and the Poids widget.
    @State private var history: CorpsStore
    /// The declared zones, followed on their own page (SHARPIT ADR-068).
    @State private var zones: SensitiveZonesStore
    /// The latest blood test heads the tables as « N biomarqueurs ».
    @State private var blood: BloodTestsStore
    @State private var isShowingBloodTests = false
    @State private var isImportingBloodTest = false
    private let profileClient: any AthleteProfileServing
    private let tokenProvider: () async throws -> String
    private let modelContext: ModelContext?

    @State private var opened: V1HealthMarker?
    @State private var isEditingWeightTarget = false
    @State private var hasAppeared = false
    @State private var reloadGate = LoadGate()

    init(
        profileClient: any AthleteProfileServing & BodyCompositionServing,
        recoveryClient: any RecoveryServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        self.profileClient = profileClient
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
        _store = State(initialValue: SanteStore(tokenProvider: tokenProvider, modelContext: modelContext))
        _zones = State(initialValue: SensitiveZonesStore(tokenProvider: tokenProvider, modelContext: modelContext))
        _blood = State(initialValue: BloodTestsStore(tokenProvider: tokenProvider))
        _history = State(initialValue: CorpsStore(
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
                    SharpitStateMessage.failed(message) { Task { await reload(force: true) } }
                case .empty:
                    // Blood tests need no wearable: they stay reachable before anything is measured.
                    VStack(spacing: SharpitSpacing.section) {
                        SharpitStateMessage(
                            title: String(localized: "Rien de mesuré pour l'instant"),
                            symbol: "heart.text.square",
                            detail: String(localized: "Active Apple Santé dans Paramètres → Sources de données : ton bilan se construira ici.")
                        )
                        BloodTestsCard(tokenProvider: tokenProvider)
                            .padding(.horizontal, SharpitSpacing.pageInset)
                            .padding(.bottom, SharpitSpacing.xl)
                    }
                case .loading, .loaded:
                    readout
                }
            }
            .cliniqueSheet(wash: .sleep, height: 240)
            .navigationTitle("Santé")
            // The title is written on the sheet, as Plan's is.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
                // The title shares the bar's row with its buttons, as on the mock-up.
                SharpitBarTitle(String(localized: "Santé"))
                if let overview = store.overview {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: SanteReadout.shareText(overview)) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
                    }
                    SharpitBarGap()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { isImportingBloodTest = true } label: {
                            Label("Analyse de sang", systemImage: "drop")
                        }
                        Button { isEditingWeightTarget = true } label: {
                            Label("Objectif de poids", systemImage: "target")
                        }
                    } label: {
                        Label("Ajouter", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(isPresented: $isShowingBloodTests) { BloodTestsView(tokenProvider: tokenProvider) }
            .navigationDestination(isPresented: $isImportingBloodTest) { BloodTestImportView(tokenProvider: tokenProvider) }
            .sheet(isPresented: $isEditingWeightTarget, onDismiss: { Task { await reload(force: true) } }) {
                WeightTargetSheet(profileClient: profileClient, tokenProvider: tokenProvider)
            }
            .sheet(item: $opened) { marker in
                markerSheet(marker)
            }
            .task { await reload() }
            // Buying Pro brings the biological age in without waiting for the next visit.
            .onChange(of: pro?.isPro) { _, _ in Task { await reload(force: true) } }
        }
    }

    private func reload(force: Bool = false) async {
        await reloadGate.run(force: force) {
            async let overview: Void = store.load()
            async let corps: Void = history.load()
            async let declared: Void = zones.load()
            async let day: Void = store.loadDay()
            async let tests: Void = blood.load()
            _ = await (overview, corps, declared, day, tests)
            return true
        }
    }

    private var readout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let overview = store.overview {
                    SanteHero(synthesis: overview.synthesis, vo2max: overview.marker(.vo2max))
                    VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                        SanteTrends(markers: SanteTrendReadout.drawable(overview.allMarkers))
                        if let latest = blood.tests.first, !latest.results.isEmpty {
                            SanteTable(
                                title: SanteReadout.biomarkers(latest.results.count),
                                rows: latest.results.map(SanteTable.Row.init)
                            ) { _ in isShowingBloodTests = true }
                        }
                        if !overview.allMarkers.isEmpty {
                            SanteTable(
                                title: SanteReadout.markers(overview.allMarkers.count),
                                rows: overview.allMarkers.map(SanteTable.Row.init)
                            ) { row in opened = overview.allMarkers.first { $0.key.rawValue == row.id } }
                        }
                        if !overview.watch.isEmpty {
                            SanteWatchSection(items: overview.watch)
                        }
                        if let day = store.dayState {
                            SanteTodaySection(state: day)
                        }
                        // What is followed on its own page, as lines of one table.
                        VStack(alignment: .leading, spacing: 0) {
                            SanteSectionTitle(String(localized: "Suivi"))
                            CliniqueDivider()
                            SensitiveZonesCard(store: zones)
                            CliniqueDivider()
                            BloodTestsCard(tokenProvider: tokenProvider, count: blood.tests.count)
                            biologicalAgeAccess(overview.synthesis)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                } else {
                    SanteSkeleton()
                        .padding(.top, 20)
                }
            }
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, SharpitSpacing.xl)
        }
        .modifier(ScrollUnderGlass())
        .refreshable { await reload(force: true) }
        .onAppear { hasAppeared = true }
    }

    /// What the biological age still needs when Pro cannot compute it yet.
    @ViewBuilder
    private func biologicalAgeAccess(_ synthesis: V1HealthSynthesis) -> some View {
        Group {
            // Below Pro the hero itself is the way to Pro.
            if !synthesis.biologicalAgeRequiresPro && synthesis.biologicalAge == nil {
                NavigationLink {
                    AccountView(profileClient: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
                } label: {
                    BiologicalAgePendingCard()
                }
                .buttonStyle(.sharpitPressable)
            }
        }
    }

    /// The Corps drawer, with its ranges, when the web keeps the marker's longer history;
    /// the marker's month otherwise.
    @ViewBuilder
    private func markerSheet(_ marker: V1HealthMarker) -> some View {
        if let key = SanteReadout.corpsKey(marker.key), let metric = history.metric(key) {
            CorpsMetricDrawer(
                metric: metric,
                target: marker.key == .weight ? history.targetWeightKg : nil,
                reading: marker
            ) { range in
                await history.series(for: metric, range: range)
            }
        } else {
            SanteMarkerSheet(marker: marker)
        }
    }
}

// MARK: - Biological age

/// Pro, but the web could not estimate it: what the estimate needs, opening Compte to fill it in.
private struct BiologicalAgePendingCard: View {
    var body: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            SanteLinkRow(title: String(localized: "Âge biologique"), detail: BiologicalAgeReadout.requirements)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre ton compte")
    }
}

// MARK: - What to watch

/// Only what deserves attention now; absent on a quiet month.
struct SanteWatchSection: View {
    let items: [V1HealthWatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SanteSectionTitle(String(localized: "À surveiller"))
            ForEach(items) { item in
                CliniqueDivider()
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(item.detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, SharpitSpacing.sm)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Markers

/// A section's name, over its table.
struct SanteSectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
            .padding(.bottom, SharpitSpacing.sm)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A line that opens a page of Santé: its name over what it holds, a status word when one is
/// owed, and the way in.
struct SanteLinkRow: View {
    let title: String
    var detail: String? = nil
    var status: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                if let detail {
                    Text(detail)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(SharpitColor.slate)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let status {
                CliniqueStatusPill(status, status: .watch)
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SharpitColor.slate)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .contentShape(.rect)
    }
}

/// A table row of Santé: a name over a line of context, an optional status pill, a figure over a
/// note.
struct SanteFigureRow: View {
    let title: String
    var subtitle: String? = nil
    var status: CliniqueStatus? = nil
    let value: String
    var unit: String? = nil
    var note: String? = nil
    var showsChevron = false

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let status {
                CliniqueStatusPill(SanteHeroReadout.word(status), status: status)
            }
            VStack(alignment: .trailing, spacing: 2) {
                (Text(value)
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    + Text(unit.map { " \($0)" } ?? "")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let note {
                    Text(note)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, SharpitSpacing.sm)
    }
}

/// Where a marker stands: its norm and the source of it, then its month against the one before.
struct SanteReadingBlock: View {
    let marker: V1HealthMarker

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            if let norm = marker.norm {
                VStack(alignment: .leading, spacing: 2) {
                    Text(norm.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(norm.tone.color)
                    Text(norm.reference)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let trend = marker.trend, let line = SanteReadout.trend(marker) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(trend.stable ? SharpitColor.foreground : trend.tone.color)
                    Text(SanteReadout.comparison(marker, trend: trend))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
            }
        }
        .cliniqueCard()
    }
}

/// A marker the web keeps no longer history for (sleep, steps, breathing): its month.
private struct SanteMarkerSheet: View {
    let marker: V1HealthMarker

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let value = SanteReadout.value(marker)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                        HStack(alignment: .lastTextBaseline, spacing: SharpitSpacing.xs) {
                            Text(value.text)
                                .font(SharpitTypography.heroScore)
                                .tracking(SharpitTypography.heroScoreTracking)
                                .foregroundStyle(SharpitColor.foreground)
                            if let unit = value.unit {
                                Text(unit)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.slate)
                            }
                        }
                        Text(SanteReadout.basis(marker))
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                    }
                    SanteReadingBlock(marker: marker)
                    if marker.series.count > 1 {
                        CorpsSparkline(points: marker.series, tone: SharpitColor.primary)
                            .frame(height: 140)
                            .padding(SharpitSpacing.md)
                            .sharpitSurface(.panel)
                    }
                    Text(SanteReadout.explanation(marker.key))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SharpitSpacing.pageInset)
            }
            .navigationTitle(SanteReadout.title(marker.key))
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
    }
}

/// Santé before the first byte: the scores and a table, redacted (`docs/adr/0008`).
private struct SanteSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            CliniqueScoreStrip {
                CliniqueScoreColumn(pillar: .nutrition, fraction: nil, symbol: "figure.stand", title: String(localized: "Âge biologique"), value: nil)
                CliniqueScoreColumn(pillar: .sleep, fraction: nil, symbol: "heart", title: String(localized: "Dans la norme"), value: nil)
                CliniqueScoreColumn(pillar: .recovery, fraction: nil, symbol: "bolt", title: "VO₂max", value: nil)
            }
            SanteTable(
                title: SanteReadout.markers(4),
                rows: (0..<4).map { SanteTable.Row(id: "\($0)", name: String(localized: "Mesure"), value: "00,0 bpm") }
            )
            .padding(.horizontal, 24)
            .redacted(reason: .placeholder)
        }
        .accessibilityHidden(true)
    }
}
