import SwiftUI

/// Plan → Objectifs: the races and figures the season is built toward.
///
/// The next race leads, on the ink plate, with the days left; then every goal as a card that
/// says where it stands before it is opened. A goal and a new goal open as pages in this
/// stack — Objectifs is already a sheet, and a sheet over a sheet hides where the athlete is.
struct GoalsView: View {
    @State private var store: GoalStore
    @State private var segment: GoalSegment = .active
    @State private var hasAppeared = false

    enum GoalSegment: Hashable {
        case active
        case completed
    }

    init(client: any GoalServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: GoalStore(client: client, tokenProvider: tokenProvider))
    }

    private var displayed: [V1Goal] {
        switch segment {
        case .active:
            store.activeGoalsOrdered.filter { $0.id != store.nextRace?.id }
        case .completed:
            store.completedGoals
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                if segment == .active, let next = store.nextRace {
                    NavigationLink(value: GoalRoute.detail(next)) {
                        NextRaceCard(goal: next)
                    }
                    .buttonStyle(.sharpitPressable)
                    .revealed(hasAppeared, index: 0)
                }

                SharpitSegmentedControl(
                    selection: $segment,
                    options: [
                        SharpitSegmentedControl<GoalSegment>.Option(value: .active, label: "En cours · \(store.activeGoals.count)"),
                        SharpitSegmentedControl<GoalSegment>.Option(value: .completed, label: "Atteints · \(store.completedGoals.count)"),
                    ]
                )
                .revealed(hasAppeared, index: 1)

                if displayed.isEmpty && !store.isLoading {
                    emptyState
                        .revealed(hasAppeared, index: 2)
                } else {
                    LazyVStack(spacing: SharpitSpacing.sm) {
                        ForEach(Array(displayed.enumerated()), id: \.element.id) { index, goal in
                            NavigationLink(value: GoalRoute.detail(goal)) {
                                GoalCard(goal: goal)
                            }
                            .buttonStyle(.sharpitPressable)
                            .contextMenu {
                                Button {
                                    Task { await store.toggleAchieved(goal) }
                                } label: {
                                    Label(goal.achieved ? "Remettre en cours" : "Marquer comme atteint",
                                          systemImage: goal.achieved ? "arrow.uturn.backward" : "checkmark.circle")
                                }
                                Button(role: .destructive) {
                                    Task { await store.delete(id: goal.id) }
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                            .revealed(hasAppeared, index: index + 2)
                        }
                    }
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, SharpitSpacing.xl)
            .animation(SharpitMotion.reveal, value: segment)
            .animation(SharpitMotion.reveal, value: store.goals)
        }
        .scrollIndicators(.hidden)
        .background(SharpitCanvasBackground())
        .navigationTitle("Objectifs")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: GoalRoute.create) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter un objectif")
            }
        }
        .navigationDestination(for: GoalRoute.self) { route in
            switch route {
            case .detail(let goal):
                GoalDetailView(goalId: goal.id, fallback: goal, store: store)
            case .create:
                GoalCreateView(store: store)
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .onAppear { hasAppeared = true }
    }

    private var emptyState: some View {
        VStack(spacing: SharpitSpacing.sm) {
            Image(systemName: segment == .active ? "flag.checkered" : "checkmark.seal")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 64, height: 64)
                .background(SharpitColor.primary.opacity(0.12), in: Circle())
            Text(segment == .active ? "Aucun objectif en cours" : "Aucun objectif atteint")
                .font(SharpitTypography.sectionTitle)
                .foregroundStyle(SharpitColor.foreground)
            Text(segment == .active
                 ? "Ajoute une course ou une cible chiffrée : le plan s'organise autour."
                 : "Tes objectifs atteints apparaîtront ici.")
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)
            if segment == .active {
                NavigationLink(value: GoalRoute.create) {
                    Label("Ajouter un objectif", systemImage: "plus")
                        .font(SharpitTypography.bodyEmphasis)
                        .padding(.horizontal, SharpitSpacing.md)
                        .padding(.vertical, SharpitSpacing.sm)
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .background(SharpitColor.primary, in: Capsule())
                }
                .buttonStyle(.sharpitPressable)
                .padding(.top, SharpitSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SharpitSpacing.xl)
        .sharpitSurface(.panelAlt)
    }
}

enum GoalRoute: Hashable {
    case detail(V1Goal)
    case create

    static func == (lhs: GoalRoute, rhs: GoalRoute) -> Bool {
        switch (lhs, rhs) {
        case let (.detail(l), .detail(r)): l.id == r.id
        case (.create, .create): true
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .detail(let goal): hasher.combine(goal.id)
        case .create: hasher.combine("create")
        }
    }
}

// MARK: - Cards

/// The race ahead, on the ink plate: days left, big, then what and where.
private struct NextRaceCard: View {
    let goal: V1Goal

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack {
                SharpitEyebrow("Prochain cap", systemImage: "flag.checkered")
                Spacer(minLength: 0)
                if let priority = goal.priority {
                    GoalPriorityChip(priority: priority, onInk: true)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: SharpitSpacing.xs) {
                Text(GoalFormat.daysValue(goal))
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .contentTransition(.numericText())
                Text(GoalFormat.daysUnit(goal))
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.7))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.5))
            }
            Text(goal.title)
                .font(SharpitTypography.verdict)
                .tracking(SharpitTypography.verdictTracking)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
                .lineLimit(2)
            Text(GoalFormat.raceLine(goal))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.7))
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
        .accessibilityElement(children: .combine)
    }
}

/// One goal: what it is, what it is for, and where it stands.
private struct GoalCard: View {
    let goal: V1Goal

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            GoalBadge(goal: goal)
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(goal.kind == .race ? GoalFormat.raceLine(goal) : GoalFormat.metricLine(goal))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: SharpitSpacing.xs)
            trailing
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        if goal.achieved {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(SharpitColor.signalRecovery)
        } else if goal.kind == .metric, let progress = goal.progressFraction {
            ZStack {
                SharpitScoreRing(fraction: progress, tone: SharpitColor.primary, lineWidth: 3.5)
                Text("\(Int((progress * 100).rounded()))")
                    .font(SharpitTypography.meta.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)
            }
            .frame(width: 44, height: 44)
        } else if let days = goal.daysRemaining, days >= 0 {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(days)")
                    .font(SharpitTypography.data)
                    .tracking(SharpitTypography.dataTracking)
                    .foregroundStyle(days <= 7 ? SharpitColor.signalCaution : SharpitColor.foreground)
                    .monospacedDigit()
                Text(days == 1 ? "jour" : "jours")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }
}

/// The detail page's hero: the ink plate for a race, the panel with a ring for a figure.
struct GoalHero: View {
    let goal: V1Goal

    var body: some View {
        if goal.kind == .race {
            race
        } else {
            metric
        }
    }

    private var race: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack {
                SharpitEyebrow(goal.achieved ? "Course courue" : (goal.phaseLabel ?? "Course"), systemImage: "flag.checkered")
                Spacer(minLength: 0)
                if let priority = goal.priority {
                    GoalPriorityChip(priority: priority, onInk: true)
                }
            }
            Text(goal.title)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
            if !goal.achieved, goal.daysRemaining != nil {
                HStack(alignment: .lastTextBaseline, spacing: SharpitSpacing.xs) {
                    Text(GoalFormat.daysValue(goal))
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    Text(GoalFormat.daysUnit(goal))
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.7))
                }
            }
            Text(GoalFormat.raceLine(goal))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.7))
            if let performance = goal.targetPerformance, !performance.isEmpty {
                Label("Objectif chrono · \(performance)", systemImage: "stopwatch")
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.highlight)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
    }

    private var metric: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitEyebrow(goal.achieved ? "Atteint" : "Objectif chiffré", systemImage: "gauge.with.dots.needle.67percent")
                Text(goal.title)
                    .font(SharpitTypography.pageTitle)
                    .tracking(SharpitTypography.pageTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text(GoalFormat.metricLine(goal))
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
                if let date = goal.targetDate {
                    Text("Échéance · \(date.sharpitFormatted(.dateTime.day().month(.wide).year()))")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Spacer(minLength: 0)
            if let progress = goal.progressFraction {
                ZStack {
                    SharpitScoreRing(fraction: progress, tone: goal.achieved ? SharpitColor.signalRecovery : SharpitColor.primary, lineWidth: 6)
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(SharpitTypography.data)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                }
                .frame(width: 88, height: 88)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

private struct GoalBadge: View {
    let goal: V1Goal

    var body: some View {
        Group {
            if goal.kind == .race, let priority = goal.priority {
                Text(priority.rawValue)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            } else {
                Image(systemName: goal.kind == .race ? "flag.fill" : "gauge.with.dots.needle.67percent")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .foregroundStyle(tone)
        .frame(width: 38, height: 38)
        .background(tone.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var tone: Color {
        if goal.achieved { return SharpitColor.signalRecovery }
        if goal.kind == .race, goal.priority != .a { return SharpitColor.mutedForeground }
        return SharpitColor.primary
    }
}

private struct GoalPriorityChip: View {
    let priority: GoalPriority
    var onInk = false

    var body: some View {
        Text("Objectif \(priority.rawValue)")
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(priority == .a ? SharpitColor.highlightForeground : (onInk ? SharpitColor.inkSurfaceForeground : SharpitColor.foreground))
            .padding(.horizontal, SharpitSpacing.xs)
            .padding(.vertical, 3)
            .background(
                priority == .a ? SharpitColor.highlight : SharpitColor.inkSurfaceForeground.opacity(onInk ? 0.16 : 0.08),
                in: Capsule()
            )
    }
}

enum GoalFormat {
    /// « 42 » days, or « J » on race day, or « — » once it is past.
    static func daysValue(_ goal: V1Goal) -> String {
        guard let days = goal.daysRemaining else { return "—" }
        if days > 0 { return "\(days)" }
        return days == 0 ? "J" : "—"
    }

    static func daysUnit(_ goal: V1Goal) -> String {
        guard let days = goal.daysRemaining else { return "" }
        if days > 1 { return "jours" }
        if days == 1 { return "jour" }
        return days == 0 ? "Jour de course" : "Épreuve passée"
    }

    /// « 12 octobre 2026 · Marathon · Paris »
    static func raceLine(_ goal: V1Goal) -> String {
        let date = goal.targetDate?.sharpitFormatted(.dateTime.day().month(.wide).year())
        return [date, goal.raceFormat, goal.location]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// « 265 / 280 W » or « Cible 280 W ».
    static func metricLine(_ goal: V1Goal) -> String {
        let unit = goal.unit.map { " \($0)" } ?? ""
        switch (goal.currentValue, goal.targetValue) {
        case let (current?, target?): return "\(number(current)) / \(number(target))\(unit)"
        case let (nil, target?): return "Cible \(number(target))\(unit)"
        default: return goal.unit ?? ""
        }
    }

    static func number(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
