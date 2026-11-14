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
            failureMessage: String(localized: "Ta charge n'a pas pu être chargée."),
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
            title: String(localized: "Effort"),
            emptySymbol: "bolt",
            unavailableTitle: String(localized: "Effort indisponible"),
            store: store,
            content: { effort in EffortSections(effort: effort) },
            emptyAction: (title: String(localized: "Synchroniser maintenant"), run: syncAndReload),
            wash: .good
        )
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct EffortSections: View {
    @Environment(ShellRouter.self) private var router
    @Environment(\.isExpertReading) private var isExpertReading
    let effort: V1EffortResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            hero
            if let overreaching = effort.overreaching {
                DayDetailAlert(
                    label: String(localized: "Surmenage fonctionnel · \(overreaching.label)"),
                    tone: RecoveryReadout.tone(for: overreaching.tone)
                )
            }
            if let performance = effort.strainPerformance, performance.dayCount > 0 {
                EffortWeekSection(performance: performance)
            }
            EffortLoadSection(load: effort.load, cardioLoad: effort.cardioLoad, isExpert: isExpertReading)
            EffortVerdictSection(effort: effort)
            EffortDaySection(active: effort.activeStrain, passive: effort.passiveStrain, signals: effort.composition.signals)
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
            CoachDiscussButton(title: String(localized: "Discuter de ma charge")) {
                router.discussWithCoach(about: CoachDiscuss.describe(.today))
            }
            DayDetailConfidenceFooter(
                pct: effort.confidencePct,
                note: String(localized: "Données \(effort.completenessLabel.lowercased())")
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 96)
    }

    /// The day's strain out of 21, where it sits against the advised zone, and what it means.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Effort du jour")
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.slate)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(EffortReadout.strain(effort.strain.score))
                        .font(SharpitTypography.system(size: 52, weight: .semibold, relativeTo: .largeTitle, digits: true))
                        .tracking(-1.5)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("sur \(EffortReadout.strainScale)")
                        .font(SharpitTypography.system(size: 19, weight: .regular, relativeTo: .title3, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                    Spacer(minLength: SharpitSpacing.xs)
                    CliniqueStatusPill(
                        EffortReadout.zoneWord(effort.targetBand?.status) ?? effort.strain.label,
                        status: EffortReadout.zoneStatus(effort.targetBand?.status) ?? RecoveryReadout.status(for: effort.strain.tone)
                    )
                }
                .accessibilityElement(children: .combine)
            }
            VStack(spacing: 8) {
                EffortTrack(score: effort.strain.score, band: effort.targetBand.map { $0.low...max($0.low, $0.high) })
                    .frame(height: 16)
                HStack {
                    Text("0")
                    Spacer()
                    if let band = effort.targetBand {
                        Text("Zone conseillée \(Int(band.low.rounded())) – \(Int(band.high.rounded()))")
                        Spacer()
                    }
                    Text("\(EffortReadout.strainScale)")
                }
                .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption, digits: true))
                .foregroundStyle(SharpitColor.slate)
            }
            if !effort.strain.subtitle.isEmpty {
                Text(effort.strain.subtitle)
                    .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line = EffortReadout.actionLine(effort) {
                Text(line)
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
        }
    }
}

/// The 0–21 scale: the advised zone in the recovery hue, the day as an ink dot.
private struct EffortTrack: View {
    let score: Double?
    let band: ClosedRange<Double>?

    var body: some View {
        GeometryReader { geo in
            let scale = Double(EffortReadout.strainScale)
            ZStack(alignment: .leading) {
                Capsule().fill(SharpitColor.tile).frame(height: 6)
                if let band {
                    Capsule().fill(SharpitColor.pillarRecovery.opacity(0.55))
                        .frame(width: geo.size.width * (band.upperBound - band.lowerBound) / scale, height: 6)
                        .offset(x: geo.size.width * band.lowerBound / scale)
                }
                if let score {
                    Circle().fill(SharpitColor.foreground)
                        .frame(width: 16, height: 16)
                        .offset(x: (geo.size.width - 16) * min(max(score / scale, 0), 1))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// A section's name on the sheet, with what it totals at the trailing edge.
private struct EffortSectionTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: SharpitSpacing.xs)
            if let trailing {
                Text(trailing)
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
        }
    }
}

/// A figure's line: its name, a status word when one is owed, the figure.
private struct EffortRow: View {
    let label: String
    let value: String
    var note: String? = nil
    var pill: (text: String, status: CliniqueStatus)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                if let note {
                    Text(note)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            if let pill { CliniqueStatusPill(pill.text, status: pill.status) }
            Text(value)
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

/// Rows split by hairlines, one above the first.
private struct EffortRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    CliniqueDivider()
                    row
                }
            }
        }
    }
}

/// The last seven days' strain as bars: in the advised zone, above it, under it, or not measured.
private struct EffortWeekSection: View {
    let performance: V1StrainPerformance

    var body: some View {
        let days = Array(performance.history.suffix(7))
        VStack(alignment: .leading, spacing: 14) {
            EffortSectionTitle(
                title: String(localized: "Effort de la semaine"),
                trailing: String(localized: "\(Int(performance.withinCount)) j sur \(Int(performance.dayCount)) dans la zone")
            )
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(days) { day in
                    VStack(spacing: 10) {
                        bar(day)
                        Text(EffortReadout.weekdayInitial(day.date))
                            .font(SharpitTypography.system(size: 12, weight: day.id == days.last?.id ? .semibold : .regular, relativeTo: .caption))
                            .foregroundStyle(day.id == days.last?.id ? SharpitColor.foreground : SharpitColor.slate)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 128, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(performance.withinCount)) jours sur \(Int(performance.dayCount)) dans la zone conseillée")
        }
    }

    @ViewBuilder
    private func bar(_ day: V1StrainPerformanceDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if let strain = day.strain {
            shape
                .fill(day.status == "within" ? SharpitColor.pillarRecovery : day.status == "above" ? SharpitColor.pillarNutrition : SharpitColor.outline)
                .frame(height: max(6, 96 * min(strain / Double(EffortReadout.strainScale), 1)))
        } else {
            shape
                .strokeBorder(SharpitColor.outline, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(height: 96 * min((day.low + day.high) / 2 / Double(EffortReadout.strainScale), 1))
        }
    }
}

/// The recommendation step: what the strain means for training, and why.
private struct EffortVerdictSection: View {
    let effort: V1EffortResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EffortSectionTitle(title: String(localized: "Ce que ça implique"))
            DayDetailVerdictCard(
                label: effort.verdict.label,
                tone: RecoveryReadout.tone(for: effort.verdict.tone),
                capacity: EffortReadout.capacity(effort.trainingCapacity),
                limitingFactor: EffortReadout.limitingFactor(effort.limitingFactor)
            )

            if !effort.rationale.isEmpty {
                DayDetailRationale(lines: effort.rationale)
            }
        }
    }
}

/// The evidence step: the week's load, the base behind it, their ratio and the form — the same
/// figures in both readings, named for the reading they are shown in (ADR 0006).
private struct EffortLoadSection: View {
    let load: V1EffortLoad
    let cardioLoad: V1EffortCardioLoad?
    let isExpert: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EffortSectionTitle(title: String(localized: "Charge"))
            EffortRows {
                EffortRow(label: EffortReadout.dailyCaption(isExpert: isExpert), value: EffortReadout.load(load.daily))
                EffortRow(
                    label: isExpert ? "TSS 7 j" : String(localized: "Charge aiguë, 7 jours"),
                    value: load.weekly > 0 ? EffortReadout.load(load.weekly) : "—"
                )
                if let chronic = load.chronicWeeklyAvg {
                    EffortRow(label: String(localized: "Charge de fond, par semaine"), value: EffortReadout.load(chronic))
                }
                EffortRow(
                    label: isExpert ? "ACWR" : String(localized: "Rapport aiguë / fond"),
                    value: EffortReadout.ramp(load.acwr),
                    pill: EffortReadout.rampZone(load.acwr).map { ($0, EffortReadout.rampStatus(load.acwr)) }
                )
                EffortRow(
                    label: EffortReadout.formCaption(isExpert: isExpert),
                    value: EffortReadout.form(load.tsb),
                    note: load.tsb == nil ? nil : String(localized: "habituelle entre −20 et +10")
                )
                if let cardioLoad {
                    EffortRow(
                        label: isExpert ? String(localized: "Cardio Load (CTL)") : String(localized: "Forme cardio"),
                        value: EffortReadout.load(cardioLoad.ctl),
                        note: String(localized: "≠ Strain du jour")
                    )
                    EffortRow(label: isExpert ? "ATL" : String(localized: "Fatigue aiguë"), value: EffortReadout.load(cardioLoad.atl))
                }
            }
        }
    }
}

/// The day in and out of training: the active and passive strain, then steps, stress and Body
/// Battery. No scale is drawn — none of the three has a personal norm yet, and a band invented
/// for the layout would read as one.
private struct EffortDaySection: View {
    let active: V1EffortStrainSplit?
    let passive: V1EffortStrainSplit?
    let signals: V1EffortDailySignals

    var body: some View {
        if active != nil || passive != nil || signals.steps != nil || signals.stress != nil || signals.bodyBattery != nil {
            VStack(alignment: .leading, spacing: 6) {
                EffortSectionTitle(title: String(localized: "Ta journée"))
                EffortRows {
                    if let active {
                        EffortRow(label: active.label, value: active.score.map { EffortReadout.strain($0) } ?? "—")
                    }
                    if let passive {
                        EffortRow(label: passive.label, value: passive.score.map { EffortReadout.strain($0) } ?? "—", note: String(localized: "Hors séance"))
                    }
                    if let steps = signals.steps {
                        EffortRow(label: String(localized: "Pas"), value: EffortReadout.steps(steps))
                    }
                    if let stress = signals.stress {
                        EffortRow(label: String(localized: "Stress"), value: "\(Int(stress.rounded())) / 100")
                    }
                    if let battery = signals.bodyBattery {
                        EffortRow(label: String(localized: "Batterie"), value: "\(Int(battery.rounded())) %")
                    }
                }
            }
        }
    }
}

/// What the strain is made of: training, the cardiovascular day, movement.
private struct EffortCompositionSection: View {
    let composition: V1EffortComposition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EffortSectionTitle(title: String(localized: "Composition de l'effort"))
            EffortRows {
                ForEach(composition.contributors) { contributor in
                    EffortRow(
                        label: contributor.label,
                        value: contributor.load.map { "\(Int($0.rounded()))" } ?? "—",
                        note: contributor.description,
                        pill: contributor.key == composition.dominantKey ? (String(localized: "Dominant"), .unknown) : nil
                    )
                    .opacity(contributor.available ? 1 : 0.55)
                }
            }
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
            EffortSectionTitle(title: String(localized: "Détail par dimension"))
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                Text("Fatigue par axe (0 = très faible, 100 = maximale). Un score bas est positif lorsque tu es frais.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(dimensions) { dimension in
                    DayDetailDimensionRow(
                        label: dimension.label,
                        description: dimension.description,
                        available: dimension.available,
                        score: dimension.score,
                        tone: EffortReadout.dimensionTone(dimension),
                        intensity: dimension.intensity,
                        tag: dimension.key == dominant && dimension.available ? String(localized: "Dominante") : nil
                    )
                }
                if missingCount > 0 {
                    Text("\(missingCount) dimension\(missingCount > 1 ? "s" : "") sans signal fiable (données d'entraînement ou subjectives absentes).")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            EffortSectionTitle(title: String(localized: "Cardio Load (CTL) vs forme"), trailing: String(localized: "\(points.count) j"))
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                Chart {
                    RuleMark(y: .value(String(localized: "Zéro"), 0.0))
                        .foregroundStyle(SharpitColor.divider)
                    ForEach(dated) { point in
                        LineMark(x: .value(String(localized: "Jour"), point.date, unit: .day), y: .value("CTL", point.ctl), series: .value(String(localized: "Série"), "CTL"))
                            .foregroundStyle(SharpitColor.primary)
                            .interpolationMethod(.monotone)
                        LineMark(x: .value(String(localized: "Jour"), point.date, unit: .day), y: .value("ATL", point.atl), series: .value(String(localized: "Série"), "ATL"))
                            .foregroundStyle(SharpitColor.signalVo2)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value(String(localized: "Jour"), point.date, unit: .day), y: .value("TSB", point.tsb), series: .value(String(localized: "Série"), "TSB"))
                            .foregroundStyle(SharpitColor.slate)
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
                        AxisGridLine().foregroundStyle(SharpitColor.divider)
                        AxisValueLabel()
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 150)
                .accessibilityLabel("Forme chronique, fatigue aiguë et forme nette sur \(points.count) jours")

                HStack(spacing: SharpitSpacing.md) {
                    legendItem(String(localized: "Forme chronique"), tone: SharpitColor.primary, dash: [])
                    legendItem(String(localized: "Fatigue aiguë"), tone: SharpitColor.signalVo2, dash: [3, 2])
                    legendItem(String(localized: "Forme nette"), tone: SharpitColor.slate, dash: [2, 2])
                    Spacer(minLength: 0)
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func legendItem(_ label: String, tone: Color, dash: [CGFloat]) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .stroke(tone, style: StrokeStyle(lineWidth: 2, dash: dash))
                .frame(width: 14, height: 2)
            Text(label)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
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
            EffortSectionTitle(title: String(localized: "Charge hebdomadaire"), trailing: String(localized: "\(weeks.count) semaines"))
            Chart {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    BarMark(x: .value(String(localized: "Semaine"), week.label), y: .value("TSS", week.tss))
                        .foregroundStyle(index == weeks.count - 1 ? SharpitColor.pillarRecovery : SharpitColor.pillarRecovery.opacity(0.35))
                        .cornerRadius(3)
                }
                if average > 0 {
                    RuleMark(y: .value(String(localized: "Moyenne"), average))
                        .foregroundStyle(SharpitColor.slate)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("moy. \(Int(average.rounded()))")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.slate)
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
                    AxisGridLine().foregroundStyle(SharpitColor.divider)
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
            .accessibilityLabel("Charge des \(weeks.count) dernières semaines")
        }
    }
}
