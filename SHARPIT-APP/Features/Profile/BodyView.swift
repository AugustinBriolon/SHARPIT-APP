import SwiftUI

/// Réglages → Corps: where the body is today, as the scale measured it.
///
/// Read-only. A weigh-in is written by a scale, not typed, and the clinical annex a Withings
/// Body Scan records — vascular age, pulse wave velocity, nerve health — stays on the web,
/// which has the room to explain it.
struct BodyView: View {
    @State private var store: BodyCompositionStore

    init(client: any BodyCompositionServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: BodyCompositionStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                content
            }
            .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Corps")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.phase == .idle { await store.load() } }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView("Lecture de tes mesures…")
                .frame(maxWidth: .infinity)
        case .unauthorized:
            Label("Session expirée. Reconnecte-toi.", systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(SharpitColor.signalCaution)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(SharpitColor.signalCaution)
        case .empty:
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                Label("Aucune pesée", systemImage: "scalemass")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text("Connecte une balance sur le web, ou active Apple Santé dans Moi pour remonter les pesées de ta montre.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        case .loaded:
            loaded
        }
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

    @ViewBuilder
    private var history: some View {
        let weighIns = store.measurements.filter { $0.weightKg != nil }
        if weighIns.count > 1 {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow("\(BodyCompositionStore.windowDays) derniers jours")
                VStack(spacing: 0) {
                    ForEach(weighIns) { measurement in
                        WeighInRow(measurement: measurement)
                        if measurement.id != weighIns.last?.id {
                            Rectangle()
                                .fill(SharpitColor.analysisGrid)
                                .frame(height: SharpitStroke.hairline)
                        }
                    }
                }
                .padding(.horizontal, SharpitSpacing.md)
                .sharpitSurface(.panel)
            }
        }
    }

    private func measuredLine(_ latest: V1BodyMeasurement) -> String {
        let day = latest.measuredAt.formatted(.dateTime.day().month(.wide))
        guard let scale = BodyCompositionReadout.scaleLabel(latest.source) else { return day }
        return "\(day) · \(scale)"
    }
}

private struct WeighInRow: View {
    let measurement: V1BodyMeasurement

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Text(measurement.measuredAt.formatted(.dateTime.day().month(.abbreviated)))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            Spacer(minLength: SharpitSpacing.xs)
            Text(ProfileFieldFormat.decimal(measurement.weightKg) + " kg")
                .font(SharpitTypography.instrument)
                .foregroundStyle(SharpitColor.foreground)
        }
        .padding(.vertical, SharpitSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}
