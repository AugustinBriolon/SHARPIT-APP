import SwiftUI

/// Réglages → Objectifs: the athlete's races and metric goals.
struct GoalsView: View {
    @State private var store: GoalStore
    @State private var showsCreateSheet = false
    @State private var selectedGoal: V1Goal?
    @State private var selectedSegment: GoalSegment = .active

    enum GoalSegment: String, CaseIterable, Identifiable {
        case active = "En cours"
        case completed = "Terminés"

        var id: String { rawValue }
    }

    init(client: any GoalServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: GoalStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Affichage", selection: $selectedSegment) {
                ForEach(GoalSegment.allCases) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.sm)

            let displayed = selectedSegment == .active ? store.activeGoals : store.completedGoals

            if displayed.isEmpty && !store.isLoading {
                ContentUnavailableView {
                    Label(
                        selectedSegment == .active ? "Aucun objectif en cours" : "Aucun objectif terminé",
                        systemImage: "flag"
                    )
                } description: {
                    Text(
                        selectedSegment == .active
                            ? "Ajoute une course ou une cible métrique pour orienter tes séances."
                            : "Tes objectifs complétés apparaîtront ici."
                    )
                } actions: {
                    if selectedSegment == .active {
                        Button("Ajouter un objectif") { showsCreateSheet = true }
                            .buttonStyle(.borderedProminent)
                            .tint(SharpitColor.primary)
                    }
                }
            } else {
                List {
                    ForEach(displayed) { goal in
                        Button {
                            selectedGoal = goal
                        } label: {
                            GoalRow(goal: goal)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await store.delete(id: goal.id) }
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                    .sharpitListRows()
                }
                .sharpitGroupedList()
            }
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Objectifs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter un objectif")
            }
        }
        .sheet(isPresented: $showsCreateSheet) {
            GoalCreateSheet(store: store)
        }
        .sheet(item: $selectedGoal) { goal in
            GoalDetailDrawer(goal: goal, store: store)
        }
        .task {
            await store.load()
        }
        .refreshable {
            await store.load()
        }
    }
}

private struct GoalRow: View {
    let goal: V1Goal

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            leadingBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)

                subtitleView

                if goal.kind == .metric, let progress = goal.progressFraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(SharpitColor.analysisGrid)
                                .frame(height: 5)
                            Capsule()
                                .fill(goal.achieved ? SharpitColor.primary : SharpitColor.primary.opacity(0.8))
                                .frame(width: max(geo.size.width * progress, 4), height: 5)
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: SharpitSpacing.xs)

            trailingStatus
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingBadge: some View {
        if goal.kind == .race, let p = goal.priority {
            Text(p.rawValue)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(p == .a ? SharpitColor.primary : SharpitColor.mutedForeground)
                .frame(width: 28, height: 28)
                .background(
                    (p == .a ? SharpitColor.primary : SharpitColor.mutedForeground).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        } else {
            Image(systemName: goal.kind == .race ? "flag.fill" : "gauge.with.dots.needle.67percent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 28, height: 28)
                .background(SharpitColor.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        if goal.kind == .race {
            let details = [goal.raceFormat, goal.location, goal.performanceAndPhaseSubtitle].compactMap { $0 }.filter { !$0.isEmpty }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        } else {
            if let cur = goal.currentValue, let tgt = goal.targetValue {
                let unitStr = goal.unit.map { " \($0)" } ?? ""
                Text("\(Self.formatNumber(cur)) / \(Self.formatNumber(tgt))\(unitStr)")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
            } else if let tgt = goal.targetValue {
                let unitStr = goal.unit.map { " \($0)" } ?? ""
                Text("Cible : \(Self.formatNumber(tgt))\(unitStr)")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        HStack(spacing: SharpitSpacing.xs) {
            if !goal.achieved, let days = goal.daysRemaining {
                Text(days >= 0 ? "J-\(days)" : "Passé")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(days <= 7 && days >= 0 ? SharpitColor.signalCaution : SharpitColor.mutedForeground)
                    .monospacedDigit()
            } else if goal.achieved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(SharpitColor.primary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))
        }
    }

    private static func formatNumber(_ num: Double) -> String {
        if num.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(num))
        }
        return String(format: "%.1f", num)
    }
}
