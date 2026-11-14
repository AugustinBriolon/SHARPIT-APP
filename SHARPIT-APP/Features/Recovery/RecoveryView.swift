import Charts
import SwiftUI

/// The signals behind the day's readiness, in the causal column: the state, what limits it,
/// what the body says this morning, how it has moved, why, how sure we are.
struct RecoveryView: View {
    @State private var store: DayResourceStore<V1RecoveryResponse>
    private let tokenProvider: () async throws -> String
    private let syncClient: any SyncServing

    init(
        client: any RecoveryServing,
        tokenProvider: @escaping () async throws -> String,
        day: Date = .now,
        dataDaysClient: any DataDaysServing = SharpitClient(),
        syncClient: any SyncServing = SharpitClient()
    ) {
        self.tokenProvider = tokenProvider
        self.syncClient = syncClient
        _store = State(initialValue: DayResourceStore(
            failureMessage: String(localized: "Ta récupération n'a pas pu être chargée."),
            tokenProvider: tokenProvider,
            day: day,
            dataDays: { try await dataDaysClient.dataDays(domain: .recovery, from: $0, to: $1, token: $2) },
            fetch: { try await client.recovery(trainingDayId: $0, token: $1) }
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
            title: String(localized: "Récupération"),
            emptySymbol: "heart.text.square",
            unavailableTitle: String(localized: "Récupération indisponible"),
            store: store,
            content: { recovery in RecoverySections(recovery: recovery) },
            emptyAction: (title: String(localized: "Synchroniser maintenant"), run: syncAndReload),
            wash: .good
        )
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct RecoverySections: View {
    @Environment(ShellRouter.self) private var router: ShellRouter?
    let recovery: V1RecoveryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            RecoveryLimitSection(recovery: recovery)
            reading
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                if !recovery.alerts.isEmpty {
                    RecoveryAlerts(alerts: recovery.alerts)
                }
                RecoveryMorningSection(recovery: recovery)
                if recovery.history.contains(where: { $0.hrv != nil }) {
                    RecoveryHistorySection(history: recovery.history, today: recovery.today)
                }
                if !recovery.keyEvidence.isEmpty {
                    RecoveryEvidenceSection(evidence: recovery.keyEvidence)
                }
            }
            .padding(.top, SharpitSpacing.section)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, SharpitSpacing.xl + 54)
    }

    @State private var ringShown: Double = 0

    /// The score in its ring, the state as the page's title, then why in a sentence.
    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(SharpitColor.divider, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ringShown)
                    .stroke(RecoveryReadout.status(for: recovery.signal.tone).mark, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(recovery.readinessScore.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(SharpitTypography.system(size: 44, weight: .semibold, relativeTo: .largeTitle, digits: true))
                        .tracking(-1.5)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("sur 100")
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            .frame(width: 126, height: 126)
            .padding(.bottom, 6)
            .onAppear {
                let target = CliniqueRingMath.trim(for: recovery.readinessScore.map { $0 / 100 })
                // Swept when the screen is opened, as Résumé's rings are; a day turned right after
                // shows its ring drawn (the day's figures change in place, never replay).
                if RecoveryRingSweep.isDue {
                    RecoveryRingSweep.lastPlayed = .now
                    SharpitMotion.run(SharpitMotion.gaugeFill) { ringShown = target }
                } else {
                    ringShown = target
                }
            }
            .onChange(of: recovery.readinessScore) { _, score in
                ringShown = CliniqueRingMath.trim(for: score.map { $0 / 100 })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recovery.readinessScore.map { String(localized: "\(Int($0.rounded())) sur 100") } ?? String(localized: "Pas encore de score"))
            Text(recovery.signal.label)
                .font(SharpitTypography.system(size: 22, weight: .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(RecoveryReadout.summary(recovery))
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .lineSpacing(3)
                .foregroundStyle(SharpitColor.slate)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    /// How far the reading can be trusted, and the way to ask the coach about it.
    private var reading: some View {
        HStack(spacing: 12) {
            Text(RecoveryReadout.reliability(recovery))
                .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                .lineSpacing(2)
                .foregroundStyle(SharpitColor.slate)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                router?.discussWithCoach(about: CoachDiscuss.describe(.today))
            } label: {
                Text("En parler au coach")
                    .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.sharpitPressable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(SharpitColor.divider, lineWidth: 1))
    }
}

private struct RecoveryAlerts: View {
    let alerts: [V1RecoveryAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            ForEach(alerts) { alert in
                CliniqueStatusPill(alert.label, status: RecoveryReadout.status(for: alert.tone))
            }
        }
    }
}

/// « Ce qui pèse »: each dimension of the readiness on a line — its name, a tag on the one that
/// limits, what was measured — beside its place on a track.
private struct RecoveryLimitSection: View {
    let recovery: V1RecoveryResponse

    var body: some View {
        let rows = RecoveryReadout.weights(recovery)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                RecoverySectionTitle(String(localized: "Ce qui pèse"))
                    .padding(.bottom, 4)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { CliniqueDivider() }
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(row.name)
                                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body))
                                    .foregroundStyle(SharpitColor.foreground)
                                if let tag = row.tag {
                                    Text(tag)
                                        .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption2, digits: true))
                                        .foregroundStyle(CliniqueStatus.watch.foreground)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 1)
                                        .background(CliniqueStatus.watch.fill, in: Capsule())
                                        .overlay(Capsule().strokeBorder(CliniqueStatus.watch.border, lineWidth: 1))
                                }
                            }
                            if let detail = row.detail {
                                Text(detail)
                                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                                    .foregroundStyle(SharpitColor.slate)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let position = row.position {
                            RecoveryTrack(position: position, status: row.status)
                                .frame(width: 104, height: 16)
                        }
                    }
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A track with the usual range marked on it and a dot where the reading sits.
private struct RecoveryTrack: View {
    let position: Double
    let status: CliniqueStatus

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SharpitColor.divider).frame(height: 4)
                Capsule().fill(SharpitColor.outline)
                    .frame(width: geo.size.width * 0.4, height: 4)
                    .offset(x: geo.size.width * 0.4)
                Circle()
                    .fill(status.mark)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(SharpitColor.card, lineWidth: 3).padding(-1.5))
                    .offset(x: (geo.size.width - 12) * position)
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// A section's name on the sheet.
private struct RecoverySectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The evidence step: the server's reading of each pillar this morning, and the intensity it
/// advises.
private struct RecoveryMorningSection: View {
    let recovery: V1RecoveryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecoverySectionTitle(String(localized: "Ce matin"))
                .padding(.bottom, 4)
            row(String(localized: "Intensité conseillée"), recovery.intensity, tone: SharpitColor.foreground)
            ForEach(recovery.pillars) { pillar in
                CliniqueDivider()
                row(RecoveryReadout.pillarCaption(pillar.key), pillar.label, tone: SharpitColor.foreground)
            }
            if let battery = recovery.today.bodyBattery {
                CliniqueDivider()
                row(String(localized: "Batterie"), "\(Int(battery.rounded())) %", tone: SharpitColor.foreground)
            }
            if let horizon = RecoveryReadout.recoveryHorizon(recovery.estimatedRecoveryDays) {
                CliniqueDivider()
                Text(horizon)
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(SharpitColor.slate)
                    .padding(.vertical, 14)
            }
            if recovery.isCalibrating {
                Text("Calibration en cours. Ta norme se construit encore.")
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(SharpitColor.slate)
            }
            if recovery.dissonanceDetected {
                CliniqueStatusPill(String(localized: "Données et ressenti divergent"), status: .watch)
                    .padding(.top, SharpitSpacing.xs)
            }
        }
    }

    private func row(_ name: String, _ value: String, tone: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Text(name)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: SharpitSpacing.sm)
            Text(value)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(tone)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
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

    private var baseline: ClosedRange<Double>? {
        guard let low = today.hrvBaselineLow, let high = today.hrvBaselineHigh, low <= high else { return nil }
        return low...high
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            RecoverySectionTitle(String(localized: "VFC · \(history.count) derniers jours"))
            SharpitScrubChart(
                points: points.map { SharpitScrubPoint(date: $0.date, value: $0.hrv) },
                band: baseline,
                axisName: "VFC",
                height: 150,
                axisLabel: { String(Int($0.rounded())) },
                readout: { "\(Int($0.rounded())) ms" }
            )
        }
    }
}

private struct RecoveryEvidenceSection: View {
    let evidence: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecoverySectionTitle(String(localized: "Ce qui l'explique"))
                .padding(.bottom, 4)
            ForEach(Array(evidence.enumerated()), id: \.offset) { index, line in
                if index > 0 { CliniqueDivider() }
                Text(line)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            }
        }
    }
}

/// When the recovery ring last swept, so turning the days does not replay it.
@MainActor
enum RecoveryRingSweep {
    static var lastPlayed: Date?

    // shortcut: a time window stands in for « the screen was just opened »; pass the scaffold's own
    // first-page flag instead if the ring ever replays on a slow swipe.
    static var isDue: Bool { lastPlayed.map { Date.now.timeIntervalSince($0) > 30 } ?? true }
}
