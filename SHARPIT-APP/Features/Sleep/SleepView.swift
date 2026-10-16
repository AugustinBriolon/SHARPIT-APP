import Charts
import SwiftUI

/// The night behind the day's sleep score: the score, time in bed and asleep, the sleep
/// coach and tonight's bedtime, the structure of the night, the sleep bank, then the
/// last fourteen nights.
struct SleepView: View {
    @State private var store: DayResourceStore<V1SleepResponse>
    @State private var showsTargets = false
    private let tokenProvider: () async throws -> String
    private let profileClient: any AthleteProfileServing
    private let syncClient: any SyncServing

    init(
        client: any SleepServing,
        tokenProvider: @escaping () async throws -> String,
        dataDaysClient: any DataDaysServing = SharpitClient(),
        syncClient: any SyncServing = SharpitClient(),
        profileClient: any AthleteProfileServing = AthleteProfileClient()
    ) {
        self.syncClient = syncClient
        self.tokenProvider = tokenProvider
        self.profileClient = profileClient
        _store = State(initialValue: DayResourceStore(
            failureMessage: "Ton sommeil n'a pas pu être chargé.",
            tokenProvider: tokenProvider,
            dataDays: { try await dataDaysClient.dataDays(domain: .sleep, from: $0, to: $1, token: $2) },
            fetch: { try await client.sleep(trainingDayId: $0, token: $1) }
        ))
    }

    /// Pulls the providers — the night may simply not have arrived yet — then reads every day again.
    private func syncAndReload() async {
        if let token = try? await tokenProvider() {
            _ = try? await syncClient.sync(token: token)
        }
        await store.reloadAll()
    }

    var body: some View {
        DayDetailScaffold(
            title: "Sommeil",
            emptySymbol: "moon.zzz",
            unavailableTitle: "Sommeil indisponible",
            store: store,
            content: { sleep in SleepSections(sleep: sleep) },
            emptyAction: (title: "Synchroniser maintenant", run: syncAndReload)
        )
        // The sleep targets, set where they are read — right of the title, beside « Aujourd'hui ».
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsTargets = true
                } label: {
                    Label("Objectifs de sommeil", systemImage: "target")
                }
            }
        }
        .sheet(isPresented: $showsTargets, onDismiss: { Task { await store.load() } }) {
            SleepTargetsSheet(profileClient: profileClient, tokenProvider: tokenProvider)
        }
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct SleepSections: View {
    let sleep: V1SleepResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            SleepHero(sleep: sleep)
            SleepCoachCard(sleep: sleep)
            if sleep.nightStatus == .present, let shares = SleepReadout.stageShares(sleep.stages) {
                SleepStructureSection(stages: sleep.stages, shares: shares)
            }
            SleepBankSection(sleep: sleep)
            if sleep.history.contains(where: { $0.minutes != nil }) {
                SleepHistorySection(history: sleep.history, targetMin: sleep.targetMin)
            }
            SharpitConfidenceLine(pct: sleep.confidencePct)
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.bottom, SharpitSpacing.xl)
    }
}

// MARK: - Score, time in bed, time asleep

private struct SleepHero: View {
    let sleep: V1SleepResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(
                title: "Score de sommeil",
                symbol: "moon.fill",
                subtitle: subtitle,
                showsChevron: false
            )

            dial

            Text(sleep.adequacy.label)
                .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if sleep.nightStatus == .present {
                Divider().overlay(SharpitColor.border)
                HStack(alignment: .top, spacing: SharpitSpacing.md) {
                    SharpitStatTile(
                        caption: "Au lit · \(SleepReadout.clock(sleep.bedtimeMin)) → \(SleepReadout.clock(sleep.wakeMin))",
                        value: SleepReadout.duration(
                            SleepReadout.timeInBed(bedtime: sleep.bedtimeMin, wake: sleep.wakeMin)
                        ),
                        isFlat: true
                    )
                    SharpitStatTile(
                        caption: durationNote,
                        value: SleepReadout.duration(sleep.durationMin),
                        isFlat: true
                    )
                }

                let parts = SleepReadout.components(sleep.breakdown)
                if !parts.isEmpty {
                    Divider().overlay(SharpitColor.border)
                    SharpitEyebrow("Ce qui l'a façonné")
                    VStack(spacing: SharpitSpacing.md) {
                        ForEach(parts, id: \.label) { part in
                            breakdownRow(part.label, part.value)
                        }
                    }
                }
            } else {
                Text(sleep.nightStatus == .pending
                     ? "La nuit n'est pas encore synchronisée."
                     : "Aucune nuit enregistrée pour ce jour.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private var subtitle: String {
        guard sleep.nightStatus == .present else { return "Cette nuit" }
        return "Cette nuit · \(SleepReadout.duration(sleep.durationMin))"
    }

    private var dial: some View {
        ZStack {
            SharpitTickGauge(score: sleep.score.map { CGFloat($0) }, showsScale: true)
            VStack(spacing: SharpitSpacing.xxs) {
                Text(sleep.score.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(SharpitTypography.system(size: 64, weight: .heavy, relativeTo: .largeTitle, digits: true))
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(sleep.score == nil ? SharpitColor.mutedForeground : SharpitColor.foreground)
                Text("sur 100")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.mutedForeground)
                if let delta = SleepReadout.scoreDelta(score: sleep.score, average: sleep.averages.score) {
                    SharpitPill(delta, style: (sleep.score ?? 0) >= (sleep.averages.score ?? 0) ? .limeSoft : .neutral)
                }
            }
            .offset(y: 8)
        }
        .padding(.horizontal, SharpitSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    private func breakdownRow(_ label: String, _ value: Double) -> some View {
        HStack(spacing: SharpitSpacing.md) {
            Text(label)
                .font(SharpitTypography.system(size: 16, weight: .medium, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 120, alignment: .leading)
            SharpitBarTrack(fraction: value / 100, tone: SharpitColor.foreground)
                .frame(height: SharpitTokens.barThickness)
            Text("\(Int(value.rounded()))")
                .font(SharpitTypography.system(size: 17, weight: .bold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var durationNote: String {
        let target = SleepReadout.duration(sleep.targetMin)
        guard let delta = SleepReadout.delta(sleep.targetDeltaMin) else { return "Endormi · sur \(target)" }
        return "Endormi · \(delta) vs \(target)"
    }
}

// MARK: - Sleep coach and tonight

/// The recommendation step: tonight's bedtime first, the coach's readings behind it, and
/// the way to ask the coach about them.
private struct SleepCoachCard: View {
    @Environment(ShellRouter.self) private var router
    let sleep: V1SleepResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(title: "Coach du sommeil", symbol: "bed.double.fill", subtitle: "Ce soir", showsChevron: false)
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                if let bedtime = sleep.recommendedBedtimeMin {
                    HStack(spacing: SharpitSpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ce soir, au lit vers")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                            Text(SleepReadout.clock(bedtime))
                                .font(SharpitTypography.system(size: 34, weight: .heavy, relativeTo: .title, digits: true))
                                .tracking(SharpitTypography.gaugeScoreTracking)
                                .foregroundStyle(SharpitColor.foreground)
                            // Callers: SleepCoachCard. API: windDownStartMin. User: fix all — P3 bedtime.
                            if let windDown = sleep.windDownStartMin {
                                Text("Coupez les écrans vers \(SleepReadout.clock(windDown))")
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                            }
                        }
                        Spacer(minLength: 0)
                        // ADR-079. Callers: SleepCoachCard. API: sleepNeededMin. User: Bevel gaps plan.
                        if let duration = sleep.sleepNeededMin ?? sleep.recommendedDurationMin {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Besoin cette nuit")
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                Text(SleepReadout.duration(duration))
                                    .font(SharpitTypography.instrument)
                                    .foregroundStyle(SharpitColor.foreground)
                            }
                        }
                    }
                    if let contributors = sleep.sleepNeededContributors {
                        let bits = [
                            contributors.debtBoostMin > 0
                                ? "dette +\(Int(contributors.debtBoostMin)) min" : nil,
                            contributors.strainBoostMin > 0
                                ? "effort +\(Int(contributors.strainBoostMin)) min" : nil,
                            contributors.efficiencyBoostMin > 0
                                ? "efficacité +\(Int(contributors.efficiencyBoostMin)) min" : nil,
                        ].compactMap { $0 }
                        if !bits.isEmpty {
                            Text(bits.joined(separator: " · "))
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                }

                if !sleep.insights.isEmpty {
                    if sleep.recommendedBedtimeMin != nil {
                        Divider().overlay(SharpitColor.border)
                    }
                    ForEach(sleep.insights, id: \.self) { insight in
                        SharpitInsightRow(
                            title: insight.title,
                            detail: insight.detail,
                            tone: SleepReadout.tone(for: insight.tone)
                        )
                    }
                }

                if let note = sleep.recoveryNote {
                    Text(note)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                CoachDiscussButton(title: "Discuter de mon sommeil") {
                    router.discussWithCoach(about: CoachDiscuss.describe(.today))
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

// MARK: - Structure

private struct SleepStructureSection: View {
    let stages: V1SleepStages
    let shares: [(stage: SleepReadout.Stage, share: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(title: "Structure du sommeil", symbol: "chart.bar.xaxis", showsChevron: false)
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(shares, id: \.stage) { item in
                            if item.share > 0 {
                                Rectangle()
                                    .fill(item.stage.tone)
                                    .frame(width: max(geo.size.width * item.share - 2, 2))
                            }
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(Capsule())

                HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                    ForEach(shares, id: \.stage) { item in
                        StageReadout(stage: item.stage, minutes: item.stage.minutes(in: stages), share: item.share)
                    }
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

private struct StageReadout: View {
    let stage: SleepReadout.Stage
    let minutes: Double?
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: SharpitSpacing.xxs + 2) {
                Circle().fill(stage.tone).frame(width: 8, height: 8)
                Text(stage.label)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }
            Text("\(Int((share * 100).rounded())) %")
                .font(SharpitTypography.data)
                .tracking(SharpitTypography.dataTracking)
                .foregroundStyle(SharpitColor.foreground)
            Text(SleepReadout.duration(minutes))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sleep bank

/// What the recent nights owe the athlete, and how steady they were.
private struct SleepBankSection: View {
    let sleep: V1SleepResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(title: "Banque de sommeil", symbol: "banknote", subtitle: "7 et 14 derniers jours", showsChevron: false)
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Solde 7 jours")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                        Text(SleepReadout.bankBalance(debtMin: sleep.debt7Min))
                            .font(SharpitTypography.system(size: 34, weight: .heavy, relativeTo: .title, digits: true))
                            .tracking(SharpitTypography.gaugeScoreTracking)
                            .foregroundStyle(SleepReadout.bankTone(debtMin: sleep.debt7Min))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Solde 14 jours")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                        Text(SleepReadout.bankBalance(debtMin: sleep.debt14Min))
                            .font(SharpitTypography.instrument)
                            .foregroundStyle(SleepReadout.bankTone(debtMin: sleep.debt14Min))
                    }
                }
                Divider().overlay(SharpitColor.border)
                HStack {
                    bankFact(
                        caption: "Moyenne 7 j",
                        value: SleepReadout.duration(sleep.averages.durationMin)
                    )
                    Spacer(minLength: 0)
                    bankFact(
                        caption: "Régularité",
                        value: sleep.regularityMin.map { "± \(Int($0.rounded())) min" } ?? "—"
                    )
                    Spacer(minLength: 0)
                    bankFact(
                        caption: "Score moyen",
                        value: sleep.averages.score.map { "\(Int($0.rounded()))" } ?? "—"
                    )
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private func bankFact(caption: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(SharpitTypography.system(size: 17, weight: .bold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
            Text(caption)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trends

private struct SleepHistorySection: View {
    let history: [V1SleepNight]
    let targetMin: Double

    /// A time axis, so the bars stay in date order whatever else the chart draws.
    private var nights: [(date: Date, minutes: Double)] {
        history.compactMap { night in
            guard let minutes = night.minutes, let date = TrainingDayId.date(night.date) else { return nil }
            return (date, minutes)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(title: "Tendances", symbol: "chart.bar.fill", subtitle: "\(history.count) dernières nuits", showsChevron: false)
            Chart {
                ForEach(nights, id: \.date) { night in
                    BarMark(
                        x: .value("Nuit", night.date, unit: .day),
                        y: .value("Heures", night.minutes / 60)
                    )
                    .foregroundStyle(night.minutes >= targetMin ? SharpitColor.foreground : SharpitColor.signalCaution)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                RuleMark(y: .value("Cible", targetMin / 60))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("cible \(SleepReadout.duration(targetMin))")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 2)) { value in
                    AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text("\(Int(hours)) h") }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}
