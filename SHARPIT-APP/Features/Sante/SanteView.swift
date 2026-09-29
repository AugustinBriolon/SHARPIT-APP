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
    private let profileClient: any AthleteProfileServing
    private let tokenProvider: () async throws -> String
    private let modelContext: ModelContext?

    @State private var opened: V1HealthMarker?
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
        _store = State(initialValue: SanteStore(tokenProvider: tokenProvider, modelContext: modelContext))
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
                    SharpitStateMessage.failed(message) { Task { await reload() } }
                case .empty:
                    SharpitStateMessage(
                        title: "Rien de mesuré pour l'instant",
                        symbol: "heart.text.square",
                        detail: "Active Apple Santé ou connecte Garmin ou une balance dans Paramètres → Sources de données : ton bilan se construira ici."
                    )
                case .loading, .loaded:
                    readout
                }
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Santé")
            // Inline: the hero is the page's headline, its halo rises under the bar.
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $isEditingWeightTarget, onDismiss: { Task { await reload() } }) {
                WeightTargetSheet(profileClient: profileClient, tokenProvider: tokenProvider)
            }
            .sheet(item: $opened) { marker in
                markerSheet(marker)
            }
            .task { await reload() }
            // Buying Pro brings the biological age in without waiting for the next visit.
            .onChange(of: pro?.isPro) { _, _ in Task { await reload() } }
        }
    }

    private func reload() async {
        async let overview: Void = store.load()
        async let corps: Void = history.load()
        _ = await (overview, corps)
    }

    private var readout: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let overview = store.overview {
                    // Full width, on the page itself: the headline is not a card.
                    SanteHero(
                        synthesis: overview.synthesis,
                        tones: overview.allMarkers.compactMap(\.norm?.tone),
                        watchCount: overview.watch.count
                    )
                    VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                        biologicalAgeAccess(overview.synthesis)
                        if !overview.watch.isEmpty {
                            SanteWatchCard(items: overview.watch)
                                .revealed(hasAppeared, index: 1)
                        }
                        section("Signes vitaux", overview.vitals, index: 2)
                        section("Corps", overview.body, index: 3)
                        section("Au quotidien", overview.daily, index: 4)
                    }
                    .padding(.horizontal, SharpitSpacing.pageInset)
                } else {
                    SanteSkeleton()
                        .padding(.horizontal, SharpitSpacing.pageInset)
                }
            }
            .padding(.bottom, SharpitSpacing.xl)
        }
        .modifier(ScrollUnderGlass())
        .refreshable { await reload() }
        .onAppear { hasAppeared = true }
    }

    /// The way to the biological age when the hero cannot show it: Pro, or the data it needs.
    @ViewBuilder
    private func biologicalAgeAccess(_ synthesis: V1HealthSynthesis) -> some View {
        Group {
            if synthesis.biologicalAgeRequiresPro {
                SharpitProTeaser(
                    title: "Âge biologique",
                    message: "Ton âge forme, calculé par SharpIt à partir de ta VO₂max."
                )
            } else if synthesis.biologicalAge == nil {
                NavigationLink {
                    AccountView(profileClient: profileClient, tokenProvider: tokenProvider, modelContext: modelContext)
                } label: {
                    BiologicalAgePendingCard()
                }
                .buttonStyle(.sharpitPressable)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ markers: [V1HealthMarker], index: Int) -> some View {
        if !markers.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow(title)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: SharpitSpacing.sm),
                              GridItem(.flexible(), spacing: SharpitSpacing.sm)],
                    spacing: SharpitSpacing.sm
                ) {
                    ForEach(markers) { marker in
                        SanteMarkerTile(marker: marker) { opened = marker }
                    }
                }
            }
            .revealed(hasAppeared, index: index)
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
        HStack(spacing: SharpitSpacing.sm) {
            SharpitRowIcon(symbol: "hourglass")
            VStack(alignment: .leading, spacing: 2) {
                Text("Âge biologique")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(BiologicalAgeReadout.requirements)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre ton compte")
    }
}

// MARK: - What to watch

/// Only what deserves attention now; absent on a quiet month.
private struct SanteWatchCard: View {
    let items: [V1HealthWatch]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(
                title: "À surveiller",
                symbol: "exclamationmark.triangle",
                tint: SharpitColor.signalCaution,
                showsChevron: false
            )
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(item.detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if item != items.last {
                    Divider().overlay(SharpitColor.signalCaution.opacity(0.2))
                }
            }
        }
        .padding(SharpitSpacing.md + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SharpitColor.signalCaution.opacity(0.1),
            in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Markers

/// One marker: its value, where it stands against its norm, where its month went, opening its
/// sheet.
struct SanteMarkerTile: View {
    let marker: V1HealthMarker
    let action: () -> Void

    var body: some View {
        let value = SanteReadout.value(marker)
        Button(action: action) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                HStack(alignment: .top, spacing: SharpitSpacing.xxs) {
                    Image(systemName: SanteReadout.symbol(marker.key))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Text(SanteReadout.title(marker.key))
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: SharpitSpacing.xs)
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xxs) {
                    Text(value.text)
                        .font(SharpitTypography.gaugeScore)
                        .tracking(SharpitTypography.gaugeScoreTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.numericText(value: marker.value))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let unit = value.unit {
                        Text(unit)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let trend = marker.trend, !trend.stable {
                        // The month's change, beside the value it moved.
                        Text(SanteReadout.signedDelta(trend.delta, for: marker.key))
                            .font(SharpitTypography.label.weight(.semibold))
                            .foregroundStyle(trend.tone == .neutral ? SharpitColor.foreground : trend.tone.color)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, SharpitSpacing.xs)
                            .padding(.vertical, 3)
                            .background(
                                (trend.tone == .neutral ? SharpitColor.mutedForeground : trend.tone.color).opacity(0.15),
                                in: Capsule()
                            )
                    }
                }
                HStack(alignment: .center, spacing: SharpitSpacing.xs) {
                    Text(marker.norm?.label ?? SanteReadout.basis(marker))
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(marker.norm?.tone.color ?? SharpitColor.mutedForeground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if marker.series.count > 2 {
                        CorpsSparkline(points: marker.series, tone: SharpitColor.primary)
                            .frame(width: 40, height: 18)
                    }
                }
            }
            .frame(minHeight: 112, alignment: .top)
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre le détail")
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
                        .foregroundStyle(SharpitColor.mutedForeground)
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
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
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
                                    .foregroundStyle(SharpitColor.mutedForeground)
                            }
                        }
                        Text(SanteReadout.basis(marker))
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
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
                        .foregroundStyle(SharpitColor.mutedForeground)
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

/// Santé before the first byte: the synthesis and two groups of tiles, redacted (`docs/adr/0008`).
private struct SanteSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            RoundedRectangle(cornerRadius: SharpitRadius.panel)
                .fill(SharpitColor.mutedForeground.opacity(0.12))
                .frame(height: 150)
            ForEach(0..<2, id: \.self) { _ in
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: SharpitSpacing.sm
                ) {
                    ForEach(0..<4, id: \.self) { _ in
                        SharpitStatTile(caption: "Mesure", value: "00,0", unit: "bpm")
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
