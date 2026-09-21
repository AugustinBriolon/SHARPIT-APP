import Charts
import SwiftUI

/// The signals behind the day's readiness, in the causal column: the state, what limits it,
/// what the body says this morning, how it has moved, why, how sure we are.
struct RecoveryView: View {
    @State private var store: DayResourceStore<V1RecoveryResponse>

    init(client: any RecoveryServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: DayResourceStore(
            failureMessage: "Ta récupération n'a pas pu être chargée.",
            tokenProvider: tokenProvider,
            fetch: { try await client.recovery(trainingDayId: $0, token: $1) }
        ))
    }

    var body: some View {
        DayDetailScaffold(
            title: "Récupération",
            emptySymbol: "heart.text.square",
            unavailableTitle: "Récupération indisponible",
            store: store
        ) { recovery in
            RecoverySections(recovery: recovery)
        }
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct RecoverySections: View {
    @Environment(ShellRouter.self) private var router
    let recovery: V1RecoveryResponse

    private var tone: Color { RecoveryReadout.tone(for: recovery.signal.tone) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            hero
            if !recovery.alerts.isEmpty {
                RecoveryAlerts(alerts: recovery.alerts)
            }
            RecoveryLimitSection(recovery: recovery)
            RecoveryMorningSection(recovery: recovery)
            if recovery.history.contains(where: { $0.hrv != nil }) {
                RecoveryHistorySection(history: recovery.history, today: recovery.today)
            }
            if !recovery.keyEvidence.isEmpty {
                RecoveryEvidenceSection(evidence: recovery.keyEvidence)
            }
            VStack(spacing: SharpitSpacing.xxs) {
                SharpitConfidenceLine(pct: recovery.confidencePct)
                Text("Données \(recovery.completenessLabel.lowercased())")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.bottom, SharpitSpacing.xl)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            CoachDiscussButton(title: "Discuter de ma récupération") {
                router.discussWithCoach(about: CoachDiscuss.describe(.today))
            }

            SharpitHeroScore(score: recovery.readinessScore, label: recovery.signal.label, tone: tone)

            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: "figure.run")
                    .foregroundStyle(SharpitColor.primary)
                Text("Intensité conseillée")
                    .foregroundStyle(SharpitColor.mutedForeground)
                Text(recovery.intensity)
                    .foregroundStyle(SharpitColor.foreground)
                    .fontWeight(.semibold)
            }
            .font(SharpitTypography.body)

            if recovery.isCalibrating {
                Label("Calibration en cours — ta norme se construit encore.", systemImage: "hourglass")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }
}

private struct RecoveryAlerts: View {
    let alerts: [V1RecoveryAlert]

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ForEach(alerts) { alert in
                let tone = RecoveryReadout.tone(for: alert.tone)
                Label(alert.label, systemImage: "exclamationmark.triangle.fill")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(tone)
                    .padding(SharpitSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        tone.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    )
            }
        }
    }
}

/// The limit step: what holds readiness back, how long until it lifts, and why.
private struct RecoveryLimitSection: View {
    let recovery: V1RecoveryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Ce qui pèse")
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                if let limiter = recovery.limiter {
                    HStack(spacing: SharpitSpacing.sm) {
                        Image(systemName: "arrow.down.forward.circle.fill")
                            .font(SharpitTypography.sectionTitle)
                            .foregroundStyle(SharpitColor.signalCaution)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Facteur limitant")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                            Text(limiter)
                                .font(SharpitTypography.cardTitle)
                                .foregroundStyle(SharpitColor.foreground)
                        }
                    }
                }
                if !recovery.dimensions.isEmpty {
                    VStack(spacing: SharpitSpacing.sm) {
                        ForEach(recovery.dimensions) { dimension in
                            DimensionBar(dimension: dimension)
                        }
                    }
                }
                if let horizon = RecoveryReadout.recoveryHorizon(recovery.estimatedRecoveryDays) {
                    Label(horizon, systemImage: "clock.arrow.circlepath")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)

            if !recovery.rationale.isEmpty {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    ForEach(recovery.rationale, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                            Image(systemName: "arrow.right")
                                .font(SharpitTypography.label)
                                .foregroundStyle(SharpitColor.primary)
                            Text(line)
                                .font(SharpitTypography.body)
                                .foregroundStyle(SharpitColor.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

private struct DimensionBar: View {
    let dimension: V1RecoveryDimension

    private var fraction: Double { min(max((dimension.score ?? 0) / 100, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            HStack {
                Text(RecoveryReadout.dimensionLabel(dimension.key))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer()
                Text(dimension.score.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(RecoveryReadout.scoreTone(dimension.score))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SharpitColor.analysisGrid)
                    Capsule()
                        .fill(RecoveryReadout.scoreTone(dimension.score))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The evidence step: what the body said this morning, against the athlete's own normal.
private struct RecoveryMorningSection: View {
    let recovery: V1RecoveryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Ce matin")
            HStack(spacing: SharpitSpacing.sm) {
                SharpitStatTile(
                    caption: "VFC",
                    value: recovery.today.hrv.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: recovery.today.hrv == nil ? nil : "ms",
                    note: RecoveryReadout.hrvNote(recovery.today),
                    tone: RecoveryReadout.hrvTone(recovery.today)
                )
                SharpitStatTile(
                    caption: "FC repos",
                    value: recovery.today.restingHr.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: recovery.today.restingHr == nil ? nil : "bpm"
                )
                if let battery = recovery.today.bodyBattery {
                    SharpitStatTile(caption: "Batterie", value: "\(Int(battery.rounded()))", unit: "%")
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SharpitSpacing.xs) {
                ForEach(recovery.pillars) { pillar in
                    PillarChip(pillar: pillar)
                }
            }
            if recovery.dissonanceDetected {
                Label("Tes données et ton ressenti ne disent pas la même chose.", systemImage: "arrow.left.arrow.right")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalCaution)
            }
        }
    }
}

private struct PillarChip: View {
    let pillar: V1RecoveryPillar

    var body: some View {
        let tone = RecoveryReadout.tone(for: pillar.tone)
        VStack(alignment: .leading, spacing: 2) {
            Text(RecoveryReadout.pillarCaption(pillar.key))
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(pillar.label)
                .font(SharpitTypography.meta)
                .fontWeight(.semibold)
                .foregroundStyle(tone)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(SharpitSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct RecoveryHistorySection: View {
    let history: [V1RecoveryDay]
    let today: V1RecoveryToday

    /// Plotted on a time axis: a categorical axis orders its values by first appearance,
    /// and the baseline band's two ends would jump ahead of the days between them.
    private var points: [(date: Date, hrv: Double)] {
        history.compactMap { day in
            guard let hrv = day.hrv, let date = TrainingDayId.date(day.date) else { return nil }
            return (date, hrv)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("VFC · \(history.count) derniers jours")
            Chart {
                if let low = today.hrvBaselineLow, let high = today.hrvBaselineHigh,
                   let first = points.first?.date, let last = points.last?.date {
                    RectangleMark(
                        xStart: .value("Début", first),
                        xEnd: .value("Fin", last),
                        yStart: .value("Norme basse", low),
                        yEnd: .value("Norme haute", high)
                    )
                    .foregroundStyle(SharpitColor.signalRecovery.opacity(0.12))
                }
                ForEach(points, id: \.date) { point in
                    LineMark(x: .value("Jour", point.date, unit: .day), y: .value("VFC", point.hrv))
                        .foregroundStyle(SharpitColor.primary)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Jour", point.date, unit: .day), y: .value("VFC", point.hrv))
                        .foregroundStyle(SharpitColor.primary)
                        .symbolSize(18)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: false)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                    AxisValueLabel()
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 150)
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
        }
    }
}

private struct RecoveryEvidenceSection: View {
    let evidence: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Ce qui l'explique")
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                ForEach(evidence, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                        Circle()
                            .fill(SharpitColor.primary)
                            .frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(line)
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
    }
}
