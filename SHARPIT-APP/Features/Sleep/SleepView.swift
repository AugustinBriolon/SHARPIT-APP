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

    init(
        client: any SleepServing,
        tokenProvider: @escaping () async throws -> String,
        profileClient: any AthleteProfileServing = AthleteProfileClient()
    ) {
        self.tokenProvider = tokenProvider
        self.profileClient = profileClient
        _store = State(initialValue: DayResourceStore(
            failureMessage: "Ton sommeil n'a pas pu être chargé.",
            tokenProvider: tokenProvider,
            fetch: { try await client.sleep(trainingDayId: $0, token: $1) }
        ))
    }

    var body: some View {
        DayDetailScaffold(
            title: "Sommeil",
            emptySymbol: "moon.zzz",
            unavailableTitle: "Sommeil indisponible",
            store: store
        ) { sleep in
            SleepSections(sleep: sleep)
        }
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

    private var tone: Color { SleepReadout.tone(for: sleep.adequacy.key) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitHeroScore(score: sleep.score, label: sleep.adequacy.label, tone: tone)

            if sleep.nightStatus == .present {
                HStack(spacing: SharpitSpacing.sm) {
                    SharpitStatTile(
                        caption: "Au lit",
                        value: SleepReadout.duration(
                            SleepReadout.timeInBed(bedtime: sleep.bedtimeMin, wake: sleep.wakeMin)
                        ),
                        note: "\(SleepReadout.clock(sleep.bedtimeMin)) → \(SleepReadout.clock(sleep.wakeMin))"
                    )
                    SharpitStatTile(
                        caption: "Sommeil",
                        value: SleepReadout.duration(sleep.durationMin),
                        note: durationNote,
                        tone: tone
                    )
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(sleep.nightStatus == .pending
                     ? "La nuit n'est pas encore synchronisée."
                     : "Aucune nuit enregistrée pour ce jour.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    private var durationNote: String {
        let target = "sur \(SleepReadout.duration(sleep.targetMin)) visées"
        guard let delta = SleepReadout.delta(sleep.targetDeltaMin) else { return target }
        return "\(delta) · \(target)"
    }
}

// MARK: - Sleep coach and tonight

/// The recommendation step: tonight's bedtime first, the coach's readings behind it, and
/// the way to ask the coach about them.
private struct SleepCoachCard: View {
    @Environment(ShellRouter.self) private var router
    let sleep: V1SleepResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Coach du sommeil")
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                if let bedtime = sleep.recommendedBedtimeMin {
                    HStack(spacing: SharpitSpacing.md) {
                        Image(systemName: "bed.double.fill")
                            .font(SharpitTypography.sectionTitle)
                            .foregroundStyle(SharpitColor.primary)
                            .frame(width: 44, height: 44)
                            .background(SharpitColor.primary.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ce soir, au lit vers")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                            Text(SleepReadout.clock(bedtime))
                                .font(SharpitTypography.data)
                                .tracking(SharpitTypography.dataTracking)
                                .foregroundStyle(SharpitColor.foreground)
                        }
                        Spacer(minLength: 0)
                        if let duration = sleep.recommendedDurationMin {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("pour dormir")
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                Text(SleepReadout.duration(duration))
                                    .font(SharpitTypography.instrument)
                                    .foregroundStyle(SharpitColor.foreground)
                            }
                        }
                    }
                }

                if !sleep.insights.isEmpty {
                    if sleep.recommendedBedtimeMin != nil {
                        Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
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
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
    }
}

// MARK: - Structure

private struct SleepStructureSection: View {
    let stages: V1SleepStages
    let shares: [(stage: SleepReadout.Stage, share: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Structure du sommeil")
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
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
        }
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
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Banque de sommeil")
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Solde 7 jours")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                        Text(SleepReadout.bankBalance(debtMin: sleep.debt7Min))
                            .font(SharpitTypography.gaugeScore)
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
                Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
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
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
        }
    }

    private func bankFact(caption: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(value)
                .font(SharpitTypography.instrument)
                .foregroundStyle(SharpitColor.foreground)
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
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Tendances · \(history.count) nuits")
            Chart {
                ForEach(nights, id: \.date) { night in
                    BarMark(
                        x: .value("Nuit", night.date, unit: .day),
                        y: .value("Heures", night.minutes / 60)
                    )
                    .foregroundStyle(night.minutes >= targetMin ? SharpitColor.signalBase : SharpitColor.signalCaution)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
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
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
        }
    }
}
