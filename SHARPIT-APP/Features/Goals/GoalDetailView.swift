import Charts
import SwiftUI

/// One goal, as a full page pushed in the Objectifs stack — not a sheet over the Objectifs
/// sheet, whose stack the athlete could not see.
///
/// The hero says where the goal stands — days to the race, or how far the figure has come —
/// then the evidence: sessions and time put in, the projection when there is one, the
/// segments, the notes, and the two actions.
struct GoalDetailView: View {
    let goalId: String
    let fallback: V1Goal
    let store: GoalStore
    @Environment(\.dismiss) private var dismiss

    @State private var isUpdating = false
    @State private var showsDeleteConfirmation = false
    @State private var isEditing = false
    @State private var hasAppeared = false
    @State private var linkedActivities: [V1GoalLinkedActivity] = []

    /// Read from the store, so validating the goal updates this page in place.
    private var goal: V1Goal {
        store.goal(id: goalId) ?? fallback
    }

    private var volumeStats: GoalVolumeStats {
        store.volumeStats(for: goal)
    }

    private var raceProjection: RaceProjectionReadout? {
        store.raceProjection(for: goal)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SharpitSpacing.md) {
                GoalHero(goal: goal)
                    .revealed(hasAppeared, index: 0)
                if goal.raceStatus == .awaitingResult {
                    RaceAwaitingResultNotice(goal: goal, store: store)
                        .revealed(hasAppeared, index: 1)
                }
                Group {
                    metricsOverviewGrid
                    // A race run reads its real legs on its session; the projected split is gone.
                    if goal.raceStatus != .done, let proj = raceProjection, !proj.legs.isEmpty {
                        projectedSplitCard(proj.legs)
                    }
                    if goal.kind == .metric {
                        metricProgressSection
                    }
                    if let notes = goal.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
                        notesCard(notes)
                    }
                    if !linkedActivities.isEmpty, store.sessionReader != nil {
                        linkedActivitiesSection
                    }
                }
                .revealed(hasAppeared, index: 1)
                // A race awaiting its result validates from its notice, above.
                if goal.raceStatus != .awaitingResult {
                    actionButtonsSection
                        .revealed(hasAppeared, index: 2)
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(goal.kind == .race ? "Course" : "Objectif")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hasAppeared = true }
        .task(id: goalId) {
            let activities = await store.linkedActivities(goalId: goalId)
            withAnimation(SharpitMotion.reveal) { linkedActivities = activities }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Modifier", systemImage: "pencil") { isEditing = true }
                    Divider()
                    SharpitDeleteMenuButton { showsDeleteConfirmation = true }
                } label: {
                    Label("Actions", systemImage: "ellipsis")
                }
                .disabled(isUpdating)
            }
        }
        .navigationDestination(isPresented: $isEditing) {
            GoalEditView(goal: goal, store: store)
        }
        .confirmationDialog(
            "Supprimer cet objectif ?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer définitivement", role: .destructive) {
                Task {
                    isUpdating = true
                    await store.delete(id: goal.id)
                    dismiss()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action supprimera l'objectif de ton plan d'entraînement.")
        }
    }

    // MARK: - Metrics Overview Grid

    private var metricsOverviewGrid: some View {
        let stats = volumeStats

        return VStack(spacing: SharpitSpacing.sm) {
            HStack(spacing: SharpitSpacing.sm) {
                metricTile(
                    title: "Séances",
                    value: "\(stats.sessionsDone)",
                    caption: stats.sessionHint,
                    symbol: "dumbbell.fill"
                )

                metricTile(
                    title: "Durée",
                    value: stats.durationLabel,
                    caption: stats.durationHint,
                    symbol: "clock.fill"
                )
            }

            if goal.raceStatus == .done, let actual = goal.result?.durationSec {
                raceOutcomeCard(actual: actual, projected: raceProjection)
            } else if goal.kind == .race {
                racePositionCard(raceProjection)
            } else if goal.kind == .metric, let cur = goal.currentValue, let tgt = goal.targetValue {
                metricPositionCard(current: cur, target: tgt)
            }
        }
    }

    private func metricTile(title: String, value: String, caption: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer()
                Image(systemName: symbol)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.primary)
            }

            Text(value)
                .font(SharpitTypography.data)
                .foregroundStyle(SharpitColor.foreground)
                .monospacedDigit()

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panelAlt)
    }

    /// The server's projection: the finish and its range, the gap to the aim, how far to trust
    /// it and what would sharpen it — or an honest line when it cannot project this race.
    private func racePositionCard(_ proj: RaceProjectionReadout?) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(title: "Position", symbol: "scope", showsChevron: false)
            if let proj {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proj.finishLabel)
                            .font(SharpitTypography.verdict)
                            .foregroundStyle(SharpitColor.foreground)
                            .monospacedDigit()
                        Text(proj.rangeLabel)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .monospacedDigit()
                    }
                    Spacer()
                    if let delta = proj.delta {
                        deltaPill(delta)
                    }
                }
                if let today = proj.todayLine {
                    Text(today)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .monospacedDigit()
                }
                if !proj.trajectory.isEmpty {
                    RaceTrajectoryChart(points: proj.trajectory, targetSec: proj.projection.targetSec)
                    if let line = proj.trajectoryLine {
                        Text(line)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.foreground)
                            .monospacedDigit()
                    }
                }
                if let confidence = proj.confidenceLine {
                    Text(confidence)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                if !proj.missing.isEmpty {
                    missingHints(proj.missing)
                }
            } else {
                Text("Projection indisponible pour ce format")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    /// What would sharpen the projection, as the server words it, and the way to fill it in.
    private func missingHints(_ hints: [String]) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            ForEach(hints, id: \.self) { hint in
                Text("· \(hint)")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.thresholdsClient != nil {
                NavigationLink(value: GoalRoute.thresholds) {
                    HStack(spacing: 4) {
                        Text("Compléter mes seuils")
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.primary)
                }
                .buttonStyle(.sharpitPressable)
                .padding(.top, SharpitSpacing.xxs)
            }
        }
    }

    private func deltaPill(_ delta: RaceDelta) -> some View {
        Text(delta.label)
            .font(.system(size: 12, weight: .bold))
            .monospacedDigit()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((delta.isAhead ? SharpitColor.primary : SharpitColor.signalCaution).opacity(0.15), in: Capsule())
            .foregroundStyle(delta.isAhead ? SharpitColor.primary : SharpitColor.signalCaution)
    }

    /// A race run: the time, the projection it was read against, and the gap to the aim.
    private func raceOutcomeCard(actual: Double, projected: RaceProjectionReadout?) -> some View {
        let delta = RaceTime.targetSeconds(from: goal.targetPerformance).map { RaceDelta(seconds: actual - $0) }
        return VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(title: "Résultat", symbol: "flag.checkered", tint: SharpitColor.signalRecovery, showsChevron: false)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RaceTime.clock(actual))
                        .font(SharpitTypography.verdict)
                        .foregroundStyle(SharpitColor.foreground)
                        .monospacedDigit()
                    if let projected {
                        Text(projected.plannedVsActual(actualSeconds: actual))
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .monospacedDigit()
                    }
                }
                Spacer()
                if let delta {
                    deltaPill(delta)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private func metricPositionCard(current: Double, target: Double) -> some View {
        let isAhead = goal.lowerIsBetter == true ? current <= target : current >= target
        let diff = current - target
        let unitStr = goal.unit.map { " " + $0 } ?? ""

        return VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack {
                Text("Position")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer()
                Image(systemName: "scope")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Self.formatNumber(current))\(unitStr)")
                        .font(SharpitTypography.verdict)
                        .foregroundStyle(SharpitColor.foreground)
                        .monospacedDigit()

                    Text("vs \(Self.formatNumber(target))\(unitStr)")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(String(format: "%+.1f%@", diff, unitStr))
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    (isAhead ? SharpitColor.primary : SharpitColor.signalCaution).opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(isAhead ? SharpitColor.primary : SharpitColor.signalCaution)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    // MARK: - Projected Split

    /// The projected legs, each with its time and, quietly, where its pace came from.
    private func projectedSplitCard(_ legs: [RaceProjectionReadout.Leg]) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitCardHeader(title: "Détail par segment", symbol: "stopwatch", showsChevron: false) {
                Text("Projection")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            RaceLegsBar(segments: legs.map(\.segment), compact: true)
            VStack(spacing: SharpitSpacing.xs) {
                ForEach(legs) { leg in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(leg.segment.label)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(leg.segment.isTransition ? SharpitColor.mutedForeground : SharpitColor.foreground)
                            if let source = leg.sourceLabel {
                                Text(source)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.8))
                            }
                        }
                        Spacer()
                        Text(leg.timeLabel)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.foreground)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panelAlt)
    }

    // MARK: - Metric Progress Section

    @ViewBuilder
    private var metricProgressSection: some View {
        if let current = goal.currentValue, let target = goal.targetValue {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                HStack {
                    Text("Progression de la métrique")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer()
                    if let pct = goal.progressFraction {
                        Text("\(Int(pct * 100))%")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.primary)
                            .monospacedDigit()
                    }
                }

                if let prog = goal.progressFraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(SharpitColor.analysisGrid)
                                .frame(height: 8)
                            Capsule()
                                .fill(SharpitColor.primary)
                                .frame(width: max(geo.size.width * prog, 6), height: 8)
                        }
                    }
                    .frame(height: 8)
                    .padding(.vertical, 4)
                }

                HStack {
                    if let start = goal.startValue {
                        Text("Départ : \(Self.formatNumber(start))\(goal.unit.map { " " + $0 } ?? "")")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    Spacer()
                    Text("Actuel : \(Self.formatNumber(current)) / \(Self.formatNumber(target))\(goal.unit.map { " " + $0 } ?? "")")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.foreground)
                        .monospacedDigit()
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panelAlt)
        }
    }

    // MARK: - Notes Card

    /// The sessions raced for this goal, each pushing its page in the Objectifs stack.
    private var linkedActivitiesSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Activités liées")
            ForEach(linkedActivities) { activity in
                NavigationLink(value: GoalRoute.activity(activity.id)) {
                    GoalLinkedActivityRow(activity: activity)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Voir la séance")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes & Stratégie")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)

            Text(notes)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panelAlt)
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: SharpitSpacing.sm) {
            Button {
                Task {
                    isUpdating = true
                    await store.toggleAchieved(goal)
                    isUpdating = false
                }
            } label: {
                HStack(spacing: SharpitSpacing.xs) {
                    if isUpdating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: goal.achieved ? "arrow.counterclockwise" : "checkmark.circle.fill")
                        Text(goal.achieved ? "Marquer comme en cours" : "Valider l'objectif")
                    }
                }
                .font(SharpitTypography.bodyEmphasis)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .sharpitContainerCorner(SharpitRadius.panel)
                .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous))
                .foregroundStyle(SharpitColor.primaryForeground)
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)
        }
        .padding(.top, SharpitSpacing.xs)
    }

    // MARK: - Helpers

    private static func formatNumber(_ num: Double) -> String {
        if num.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(num))
        }
        return String(format: "%.1f", num)
    }
}

/// One session linked to the goal: its sport, title, day and time.
private struct GoalLinkedActivityRow: View {
    let activity: V1GoalLinkedActivity

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(sharpitSymbol: activity.type.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SharpitSportTone.label(for: activity.type))
                .frame(width: 38, height: 38)
                .sharpitConcentricBackground(SharpitSportTone.background(for: activity.type), minimum: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title ?? activity.type.label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meta)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
            }
            Spacer(minLength: SharpitSpacing.xs)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.5))
                .accessibilityHidden(true)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        [ActivityFormat.dayLabel(for: activity.date), activity.duration.map { RaceTime.clock($0) }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// The race-day projection week after week, faster reading upward, against the target.
private struct RaceTrajectoryChart: View {
    let points: [RaceProjectionReadout.TrajectoryPoint]
    let targetSec: Double?

    var body: some View {
        Chart {
            if let targetSec {
                RuleMark(y: .value("Objectif", targetSec))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(points, id: \.date) { point in
                LineMark(x: .value("Semaine", point.date), y: .value("Arrivée", point.finishSec))
                    .foregroundStyle(SharpitColor.primary)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Semaine", point.date), y: .value("Arrivée", point.finishSec))
                    .foregroundStyle(SharpitColor.primary)
                    .symbolSize(point == points.last ? 36 : 14)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(GoalAnalyticsEngine.formatDuration(seconds))
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .frame(height: 90)
        .accessibilityLabel("Trajectoire de la projection")
    }
}
