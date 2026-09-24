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
    @State private var hasAppeared = false

    /// Read from the store, so validating the goal updates this page in place.
    private var goal: V1Goal {
        store.goal(id: goalId) ?? fallback
    }

    private var volumeStats: GoalVolumeStats {
        store.volumeStats(for: goal)
    }

    private var raceProjection: GoalRaceProjectionResult? {
        store.raceProjection(for: goal)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SharpitSpacing.md) {
                GoalHero(goal: goal)
                    .revealed(hasAppeared, index: 0)
                Group {
                    metricsOverviewGrid
                    if let proj = raceProjection, !proj.segments.isEmpty {
                        segmentsCard(proj.segments)
                    }
                    if goal.kind == .metric {
                        metricProgressSection
                    }
                    if let notes = goal.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
                        notesCard(notes)
                    }
                }
                .revealed(hasAppeared, index: 1)
                actionButtonsSection
                    .revealed(hasAppeared, index: 2)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(goal.kind == .race ? "Course" : "Objectif")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hasAppeared = true }
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

            if let proj = raceProjection {
                racePositionCard(proj: proj)
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

    private func racePositionCard(proj: GoalRaceProjectionResult) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
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
                    Text(proj.projectedLabel)
                        .font(SharpitTypography.verdict)
                        .foregroundStyle(SharpitColor.foreground)
                        .monospacedDigit()

                    Text("vs \(proj.targetLabel)")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: proj.isAhead ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                    Text(proj.gapLabel)
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    (proj.isAhead ? SharpitColor.primary : SharpitColor.signalCaution).opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(proj.isAhead ? SharpitColor.primary : SharpitColor.signalCaution)
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

    // MARK: - Segments Card

    private func segmentsCard(_ segments: [GoalPositionSegment]) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack {
                Text("Détail par segment")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer()
                Text("Projection")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            // Visual segmented bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segments) { seg in
                        let width = max(geo.size.width * Double(seg.sharePct) / 100.0 - 2, 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(segmentColor(for: seg.kind))
                            .frame(width: width, height: 6)
                    }
                }
            }
            .frame(height: 6)
            .padding(.vertical, 2)

            VStack(spacing: 6) {
                ForEach(segments) { seg in
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(segmentColor(for: seg.kind))
                                .frame(width: 8, height: 8)
                            Text(seg.label)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.foreground)
                        }
                        Spacer()
                        Text(seg.timeLabel)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.foreground)
                            .monospacedDigit()
                        Text("(\(seg.sharePct)%)")
                            .font(.system(size: 11))
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panelAlt)
    }

    private func segmentColor(for kind: String) -> Color {
        switch kind {
        case "swim": SharpitSportColor.color(SharpitSportColor.swim)
        case "bike": SharpitSportColor.color(SharpitSportColor.bike)
        case "run": SharpitSportColor.color(SharpitSportColor.run)
        case "t1", "t2": SharpitColor.mutedForeground.opacity(0.6)
        default: SharpitColor.primary
        }
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
                    SharpitHaptics.play(.success)
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
                .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous))
                .foregroundStyle(SharpitColor.primaryForeground)
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                HStack(spacing: SharpitSpacing.xs) {
                    Image(systemName: "trash")
                    Text("Supprimer cet objectif")
                }
                .font(SharpitTypography.body)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    SharpitColor.destructive.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                )
                .foregroundStyle(SharpitColor.destructive)
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
