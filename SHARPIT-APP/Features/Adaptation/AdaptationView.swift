import SwiftUI

/// Whether the training is working, in the causal column: the adaptation index and its trend,
/// what it means for the next block, what holds it back, the dimensions behind it, the
/// evidence and how sure the reading is. A day drill-down like Recovery: the web's
/// `/plan/adaptation` — the body's answer to the load, never « Ajuster le planning ».
struct AdaptationView: View {
    @State private var store: DayResourceStore<V1AdaptationResponse>
    private let tokenProvider: () async throws -> String
    private let syncClient: any SyncServing

    init(
        client: any AdaptationServing,
        tokenProvider: @escaping () async throws -> String,
        dataDaysClient: any DataDaysServing = SharpitClient(),
        syncClient: any SyncServing = SharpitClient()
    ) {
        self.tokenProvider = tokenProvider
        self.syncClient = syncClient
        _store = State(initialValue: DayResourceStore(
            failureMessage: "Ton adaptation n'a pas pu être chargée.",
            tokenProvider: tokenProvider,
            dataDays: { try await dataDaysClient.dataDays(domain: .adaptation, from: $0, to: $1, token: $2) },
            fetch: { try await client.adaptation(trainingDayId: $0, token: $1) }
        ))
    }

    /// Pulls the providers, then reads every day again.
    private func syncAndReload() async {
        if let token = try? await tokenProvider() {
            _ = try? await syncClient.sync(token: token)
        }
        await store.reloadAll()
    }

    var body: some View {
        DayDetailScaffold(
            title: "Adaptation",
            emptySymbol: "arrow.triangle.2.circlepath",
            unavailableTitle: "Adaptation indisponible",
            store: store,
            content: { adaptation in AdaptationSections(adaptation: adaptation) },
            emptyAction: (title: "Synchroniser maintenant", run: syncAndReload)
        )
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct AdaptationSections: View {
    @Environment(ShellRouter.self) private var router
    let adaptation: V1AdaptationResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            hero
            if adaptation.plateauRisk {
                DayDetailAlert(
                    label: "Plateau · ton adaptation stagne sur la fenêtre récente.",
                    tone: SharpitColor.signalCaution
                )
            }
            if adaptation.overreachingWithoutAdaptation {
                DayDetailAlert(
                    label: "Surcharge sans gain · charge haute sans réponse adaptative en face.",
                    tone: SharpitColor.signalRisk
                )
            }
            AdaptationVerdictSection(adaptation: adaptation)
            AdaptationDimensionsSection(adaptation: adaptation)
            if !adaptation.keyEvidence.isEmpty {
                DayDetailEvidenceSection(evidence: adaptation.keyEvidence)
            }
            DayDetailConfidenceFooter(
                pct: adaptation.confidencePct,
                note: AdaptationReadout.history(adaptation.historyLength)
            )
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.bottom, SharpitSpacing.xl)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitHeroScore(
                score: adaptation.index,
                label: adaptation.status.label,
                tone: RecoveryReadout.tone(for: adaptation.status.tone)
            )
            if let trend = AdaptationReadout.trend(adaptation.trendLabel) {
                Label(trend, systemImage: "chart.line.uptrend.xyaxis")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            CoachDiscussButton(title: "Discuter de mon adaptation") {
                router.discussWithCoach(about: CoachDiscuss.describe(.today))
            }
            .padding(.top, SharpitSpacing.xxs)
        }
    }
}

/// The recommendation and the limit: the verdict, the brake and the next block's load, why.
private struct AdaptationVerdictSection: View {
    let adaptation: V1AdaptationResponse

    private var limitingScore: Double? { AdaptationReadout.limitingScore(adaptation) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Ce que ça implique")
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "arrow.forward.circle")
                    .font(SharpitTypography.sectionTitle)
                    .foregroundStyle(RecoveryReadout.tone(for: adaptation.verdict.tone))
                    .accessibilityHidden(true)
                Text(adaptation.verdict.label)
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(RecoveryReadout.tone(for: adaptation.verdict.tone))
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)

            HStack(spacing: SharpitSpacing.sm) {
                SharpitStatTile(
                    caption: adaptation.limitingFactor ?? "Frein",
                    value: limitingScore.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: limitingScore == nil ? nil : "/100",
                    note: adaptation.limitingFactor == nil ? nil : "ce qui freine le plus",
                    tone: AdaptationReadout.limiterTone(limitingScore)
                )
                SharpitStatTile(
                    caption: "Charge suivante",
                    value: AdaptationReadout.loadMultiplier(adaptation.loadMultiplier),
                    note: AdaptationReadout.loadMultiplierNote(adaptation.loadMultiplier)
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            if !adaptation.rationale.isEmpty {
                DayDetailRationale(lines: adaptation.rationale)
            }
        }
    }
}

/// The dimensions, the brake first and marked. Higher is better.
private struct AdaptationDimensionsSection: View {
    let adaptation: V1AdaptationResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Dimensions")
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                ForEach(AdaptationReadout.displayedDimensions(adaptation)) { dimension in
                    DayDetailDimensionRow(
                        label: dimension.label,
                        description: dimension.description,
                        available: dimension.available,
                        score: dimension.score,
                        tone: AdaptationReadout.dimensionTone(dimension),
                        tag: dimension.isLimiting ? "Frein" : nil
                    )
                }
                if AdaptationReadout.isNeuromuscularMissing(adaptation) {
                    Text("Efficacité neuromusculaire indisponible — moyenne de dérive FC sur 14 jours. Il faut au moins une sortie course/vélo ≥ 30 min avec stream FC + vitesse GPS (ou puissance) dans cette fenêtre.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
    }
}
