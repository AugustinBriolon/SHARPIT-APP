import Charts
import SwiftUI

/// What the day cost and what it implies, in the causal column: the strain, the verdict and
/// why, the load behind it, the five fatigue dimensions, the curves (expert reading), the
/// evidence and how sure the reading is. A day drill-down like Recovery: the web's `/plan/charge`.
struct EffortView: View {
    @State private var store: DayResourceStore<V1EffortResponse>
    private let tokenProvider: () async throws -> String
    private let syncClient: any SyncServing

    init(
        client: any EffortServing,
        tokenProvider: @escaping () async throws -> String,
        dataDaysClient: any DataDaysServing = SharpitClient(),
        syncClient: any SyncServing = SharpitClient()
    ) {
        self.tokenProvider = tokenProvider
        self.syncClient = syncClient
        _store = State(initialValue: DayResourceStore(
            failureMessage: "Ta charge n'a pas pu être chargée.",
            tokenProvider: tokenProvider,
            dataDays: { try await dataDaysClient.dataDays(domain: .effort, from: $0, to: $1, token: $2) },
            fetch: { try await client.effort(trainingDayId: $0, token: $1) }
        ))
    }

    /// Pulls the providers — the session may simply not have arrived yet — then reads every day again.
    private func syncAndReload() async {
        if let token = try? await tokenProvider() {
            _ = try? await syncClient.sync(token: token)
        }
        await store.reloadAll()
    }

    var body: some View {
        DayDetailScaffold(
            title: "Effort",
            emptySymbol: "bolt",
            unavailableTitle: "Effort indisponible",
            store: store,
            content: { effort in EffortSections(effort: effort) },
            emptyAction: (title: "Synchroniser maintenant", run: syncAndReload)
        )
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct EffortSections: View {
    @Environment(ShellRouter.self) private var router
    @Environment(\.isExpertReading) private var isExpertReading
    let effort: V1EffortResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            hero
            if let overreaching = effort.overreaching {
                DayDetailAlert(
                    label: "Surmenage fonctionnel · \(overreaching.label)",
                    tone: RecoveryReadout.tone(for: overreaching.tone)
                )
            }
            EffortVerdictSection(effort: effort)
            EffortLoadSection(load: effort.load, isExpert: isExpertReading)
            EffortDailySignalsSection(signals: effort.composition.signals)
            if effort.composition.available, !effort.composition.contributors.isEmpty {
                EffortCompositionSection(composition: effort.composition)
            }
            EffortDimensionsSection(dimensions: effort.dimensions, dominant: effort.dominantDimension)
            // The curves are the training-load vocabulary: shown to the athlete who asked for
            // it, held back from the one who did not — as the web's `ExpertOnly` does.
            if isExpertReading {
                if effort.pmc.count > 1 {
                    EffortPmcSection(points: effort.pmc)
                }
                if effort.weeklyTss.contains(where: { $0.tss > 0 }) {
                    EffortWeeklyTssSection(weeks: effort.weeklyTss, average: effort.load.avgWeeklyTss)
                }
            }
            if !effort.keyEvidence.isEmpty {
                DayDetailEvidenceSection(evidence: effort.keyEvidence)
            }
            DayDetailConfidenceFooter(
                pct: effort.confidencePct,
                note: "Données \(effort.completenessLabel.lowercased())"
            )
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.bottom, SharpitSpacing.xl)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitHeroScore(
                score: effort.strain.score,
                label: effort.strain.label,
                tone: RecoveryReadout.tone(for: effort.strain.tone),
                scale: EffortReadout.strainScale,
                fractionDigits: 1
            )
            if !effort.strain.subtitle.isEmpty {
                Text(effort.strain.subtitle)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line = EffortReadout.actionLine(effort) {
                Label(line, systemImage: "clock.arrow.circlepath")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            CoachDiscussButton(title: "Discuter de ma charge") {
                router.discussWithCoach(about: CoachDiscuss.describe(.today))
            }
            .padding(.top, SharpitSpacing.xxs)
        }
    }
}

/// The recommendation step: what the strain means for training, and why.
private struct EffortVerdictSection: View {
    let effort: V1EffortResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Ce que ça implique")
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                HStack(spacing: SharpitSpacing.sm) {
                    Image(systemName: "arrow.forward.circle")
                        .font(SharpitTypography.sectionTitle)
                        .foregroundStyle(RecoveryReadout.tone(for: effort.verdict.tone))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(effort.verdict.label)
                            .font(SharpitTypography.cardTitle)
                            .foregroundStyle(RecoveryReadout.tone(for: effort.verdict.tone))
                        if let capacity = EffortReadout.capacity(effort.trainingCapacity) {
                            Text(capacity)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                }
                if let limiting = effort.limitingFactor, !limiting.isEmpty {
                    HStack(spacing: SharpitSpacing.xs) {
                        Text("Facteur limitant")
                            .foregroundStyle(SharpitColor.mutedForeground)
                        Text(limiting)
                            .foregroundStyle(SharpitColor.foreground)
                            .fontWeight(.semibold)
                    }
                    .font(SharpitTypography.meta)
                }
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)

            if !effort.rationale.isEmpty {
                DayDetailRationale(lines: effort.rationale)
            }
        }
    }
}

/// The evidence step: the day's load, the week's, the ramp and the form — the same figures in
/// both readings, named for the reading they are shown in (ADR 0006).
private struct EffortLoadSection: View {
    let load: V1EffortLoad
    let isExpert: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Charge")
            Grid(horizontalSpacing: SharpitSpacing.sm, verticalSpacing: SharpitSpacing.sm) {
                GridRow {
                    SharpitStatTile(
                        caption: EffortReadout.dailyCaption(isExpert: isExpert),
                        value: EffortReadout.load(load.daily)
                    )
                    SharpitStatTile(
                        caption: EffortReadout.weeklyCaption(isExpert: isExpert),
                        value: load.weekly > 0 ? EffortReadout.load(load.weekly) : "—"
                    )
                }
                GridRow {
                    SharpitStatTile(
                        caption: EffortReadout.rampCaption(isExpert: isExpert),
                        value: EffortReadout.ramp(load.acwr),
                        note: EffortReadout.rampZone(load.acwr),
                        tone: EffortReadout.rampTone(load.acwr)
                    )
                    SharpitStatTile(
                        caption: EffortReadout.formCaption(isExpert: isExpert),
                        value: EffortReadout.form(load.tsb),
                        note: load.tsb == nil ? nil : "habituelle entre −20 et +10",
                        tone: EffortReadout.formTone(load.tsb)
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The day outside training: steps, stress, Body Battery. No scale is drawn — none of the
/// three has a personal norm yet, and a band invented for the layout would read as one.
private struct EffortDailySignalsSection: View {
    let signals: V1EffortDailySignals

    var body: some View {
        if signals.steps != nil || signals.stress != nil || signals.bodyBattery != nil {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow("Ta journée")
                HStack(spacing: SharpitSpacing.sm) {
                    SharpitStatTile(caption: "Pas", value: signals.steps.map { EffortReadout.steps($0) } ?? "—")
                    SharpitStatTile(
                        caption: "Stress",
                        value: signals.stress.map { "\(Int($0.rounded()))" } ?? "—",
                        unit: signals.stress == nil ? nil : "/100"
                    )
                    SharpitStatTile(
                        caption: "Batterie",
                        value: signals.bodyBattery.map { "\(Int($0.rounded()))" } ?? "—",
                        unit: signals.bodyBattery == nil ? nil : "%"
                    )
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// What the strain is made of: training, the cardiovascular day, movement.
private struct EffortCompositionSection: View {
    let composition: V1EffortComposition

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Composition de l'effort")
            VStack(spacing: SharpitSpacing.sm) {
                ForEach(composition.contributors) { contributor in
                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: SharpitSpacing.xs) {
                                Text(contributor.label)
                                    .font(SharpitTypography.bodyEmphasis)
                                    .foregroundStyle(contributor.available ? SharpitColor.foreground : SharpitColor.mutedForeground)
                                if contributor.key == composition.dominantKey {
                                    SharpitInlineTag("Dominant")
                                }
                            }
                            Text(contributor.description)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: SharpitSpacing.xs)
                        Text(contributor.load.map { "\(Int($0.rounded()))" } ?? "—")
                            .font(SharpitTypography.instrument)
                            .foregroundStyle(contributor.available ? SharpitColor.foreground : SharpitColor.mutedForeground)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
    }
}

/// The five fatigue dimensions, missing ones included. Higher is worse.
private struct EffortDimensionsSection: View {
    let dimensions: [V1EffortDimension]
    let dominant: String?

    private var missingCount: Int { dimensions.filter { !$0.available }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Détail par dimension")
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                Text("Fatigue par axe (0 = très faible, 100 = maximale). Un score bas est positif lorsque tu es frais.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(dimensions) { dimension in
                    DayDetailDimensionRow(
                        label: dimension.label,
                        description: dimension.description,
                        available: dimension.available,
                        score: dimension.score,
                        tone: EffortReadout.dimensionTone(dimension),
                        intensity: dimension.intensity,
                        tag: dimension.key == dominant && dimension.available ? "Dominante" : nil
                    )
                }
                if missingCount > 0 {
                    Text("\(missingCount) dimension\(missingCount > 1 ? "s" : "") sans signal fiable (données d'entraînement ou subjectives absentes).")
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

/// Chronic form, acute fatigue and net form over the window ending on the day.
private struct EffortPmcSection: View {
    let points: [V1EffortPmcPoint]

    private struct Point: Identifiable {
        let date: Date
        let ctl: Double
        let atl: Double
        let tsb: Double
        var id: Date { date }
    }

    /// Plotted on a time axis, as Recovery's HRV is: a categorical axis would order by first appearance.
    private var dated: [Point] {
        points.compactMap { point in
            guard let date = TrainingDayId.date(point.date) else { return nil }
            return Point(date: date, ctl: point.ctl, atl: point.atl, tsb: point.tsb)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Charge vs forme · \(points.count) jours")
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                Chart {
                    RuleMark(y: .value("Zéro", 0.0))
                        .foregroundStyle(SharpitColor.analysisGrid)
                    ForEach(dated) { point in
                        LineMark(x: .value("Jour", point.date, unit: .day), y: .value("CTL", point.ctl), series: .value("Série", "CTL"))
                            .foregroundStyle(SharpitColor.primary)
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Jour", point.date, unit: .day), y: .value("ATL", point.atl), series: .value("Série", "ATL"))
                            .foregroundStyle(SharpitColor.signalVo2)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Jour", point.date, unit: .day), y: .value("TSB", point.tsb), series: .value("Série", "TSB"))
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: false)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                        AxisValueLabel()
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 150)
                .accessibilityLabel("Forme chronique, fatigue aiguë et forme nette sur \(points.count) jours")

                HStack(spacing: SharpitSpacing.md) {
                    legendItem("Forme chronique", tone: SharpitColor.primary, dash: [])
                    legendItem("Fatigue aiguë", tone: SharpitColor.signalVo2, dash: [3, 2])
                    legendItem("Forme nette", tone: SharpitColor.mutedForeground, dash: [2, 2])
                    Spacer(minLength: 0)
                }
                .accessibilityHidden(true)
            }
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
        }
    }

    private func legendItem(_ label: String, tone: Color, dash: [CGFloat]) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .stroke(tone, style: StrokeStyle(lineWidth: 2, dash: dash))
                .frame(width: 14, height: 2)
            Text(label)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Eight weeks of load, this one last, against their average.
private struct EffortWeeklyTssSection: View {
    let weeks: [V1EffortWeek]
    let average: Double

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Charge hebdomadaire · \(weeks.count) semaines")
            Chart {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    BarMark(x: .value("Semaine", week.label), y: .value("TSS", week.tss))
                        .foregroundStyle(index == weeks.count - 1 ? SharpitColor.primary : SharpitColor.primary.opacity(0.35))
                        .cornerRadius(3)
                }
                if average > 0 {
                    RuleMark(y: .value("Moyenne", average))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("moy. \(Int(average.rounded()))")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(SharpitTypography.meta)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
            .accessibilityLabel("Charge des \(weeks.count) dernières semaines")
        }
    }
}
