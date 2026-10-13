import SwiftData
import SwiftUI

/// Plan → Objectifs: the races and figures the season is built toward.
///
/// One list, no tabs: the next race leads on the ink plate, then the goals in progress, then —
/// further down, only when there are any — the ones reached. A goal and a new goal open as pages
/// in this stack. The store is Plan's, so reopening shows the goals at once and refreshes them
/// quietly.
struct GoalsView: View {
    @State private var store: GoalStore
    @State private var hasAppeared = false
    @Environment(\.modelContext) private var modelContext

    init(store: GoalStore) {
        _store = State(initialValue: store)
    }

    private var inProgress: [V1Goal] {
        store.activeGoalsOrdered.filter { $0.id != store.nextRace?.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                if let next = store.nextRace {
                    NavigationLink(value: GoalRoute.detail(next)) {
                        NextRaceCard(goal: next)
                    }
                    .buttonStyle(.sharpitPressable)
                    .revealed(hasAppeared, index: 0)
                }

                ForEach(store.racesAwaitingResult) { race in
                    RaceAwaitingResultNotice(goal: race, store: store)
                        .revealed(hasAppeared, index: 0)
                }

                if store.goals.isEmpty && store.isLoading {
                    // The cards' own shape while the goals load, never a blank page.
                    LazyVStack(spacing: SharpitSpacing.sm) {
                        ForEach(V1Goal.placeholders) { GoalCard(goal: $0) }
                    }
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Chargement des objectifs")
                } else if store.activeGoals.isEmpty {
                    emptyState
                        .revealed(hasAppeared, index: 1)
                } else if !inProgress.isEmpty {
                    goalList(title: "En cours", goals: inProgress, startIndex: 1)
                }

                if !store.completedGoals.isEmpty {
                    goalList(title: "Atteints", goals: store.completedGoals, startIndex: inProgress.count + 2)
                        .opacity(0.8)
                }

                if !store.recentAchievements.isEmpty {
                    achievementList
                        .revealed(hasAppeared, index: inProgress.count + store.completedGoals.count + 3)
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, SharpitSpacing.xl)
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
            case .activity(let id):
                if let reader = store.sessionReader {
                    ActivityDetailView(activity: id, client: reader, tokenProvider: store.tokenProvider)
                }
            case .thresholds:
                if let client = store.thresholdsClient {
                    ThresholdsView(client: client, tokenProvider: store.tokenProvider, modelContext: modelContext)
                }
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .onAppear { hasAppeared = true }
    }

    private func goalList(title: String, goals: [V1Goal], startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("\(title) · \(goals.count)")
            LazyVStack(spacing: SharpitSpacing.sm) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
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
                    .revealed(hasAppeared, index: startIndex + index)
                }
            }
        }
    }

    /// « Réalisations récentes »: each time a goal was reached, as the web lists them under its
    /// goals — the figure, the period, the day, and the session that did it when there is one.
    private var achievementList: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Réalisations récentes")
            LazyVStack(spacing: SharpitSpacing.sm) {
                ForEach(store.recentAchievements) { achievement in
                    if let activity = achievement.activity, store.sessionReader != nil {
                        NavigationLink(value: GoalRoute.activity(activity.id)) {
                            GoalAchievementRow(achievement: achievement, opensSession: true)
                        }
                        .buttonStyle(.sharpitPressable)
                        .accessibilityHint("Voir la séance")
                    } else {
                        GoalAchievementRow(achievement: achievement, opensSession: false)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: SharpitSpacing.sm) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 64, height: 64)
                .background(SharpitColor.primary.opacity(0.12), in: Circle())
            Text("Aucun objectif en cours")
                .font(SharpitTypography.sectionTitle)
                .foregroundStyle(SharpitColor.foreground)
            Text("Ajoute une course ou une cible chiffrée : le plan s'organise autour.")
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)
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
        .frame(maxWidth: .infinity)
        .padding(SharpitSpacing.xl)
        .sharpitSurface(.panelAlt)
    }
}

enum GoalRoute: Hashable {
    case detail(V1Goal)
    case create
    /// The session that reached a goal, from « Réalisations récentes ».
    case activity(String)
    /// « Seuils & repères », from a projection's missing hints.
    case thresholds

    static func == (lhs: GoalRoute, rhs: GoalRoute) -> Bool {
        switch (lhs, rhs) {
        case let (.detail(l), .detail(r)): l.id == r.id
        case (.create, .create): true
        case let (.activity(l), .activity(r)): l == r
        case (.thresholds, .thresholds): true
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .detail(let goal): hasher.combine(goal.id)
        case .create: hasher.combine("create")
        case .activity(let id):
            hasher.combine("activity")
            hasher.combine(id)
        case .thresholds: hasher.combine("thresholds")
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
                Text(goal.kind == .race ? GoalFormat.raceCardLine(goal) : GoalFormat.metricLine(goal))
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
        if goal.isReached {
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

/// One time a goal was reached: the goal, then what, when and how, in the web's words.
private struct GoalAchievementRow: View {
    let achievement: V1GoalAchievement
    let opensSession: Bool

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Image(systemName: "trophy")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SharpitColor.signalRecovery)
                .frame(width: 38, height: 38)
                .background(SharpitColor.signalRecovery.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(achievement.goal.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(GoalAchievementReadout.line(achievement))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .monospacedDigit()
            }
            Spacer(minLength: SharpitSpacing.xs)
            if opensSession {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.5))
                    .accessibilityHidden(true)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
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
                SharpitEyebrow(goal.isReached ? "Course courue" : (goal.phaseLabel ?? "Course"), systemImage: "flag.checkered")
                Spacer(minLength: 0)
                if let priority = goal.priority {
                    GoalPriorityChip(priority: priority, onInk: true)
                }
            }
            Text(goal.title)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
            if goal.isReached, goal.result?.durationSec != nil {
                Text(GoalFormat.doneLine(goal))
                    .font(SharpitTypography.verdict)
                    .tracking(SharpitTypography.verdictTracking)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if !goal.isReached, goal.daysRemaining != nil {
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
        if goal.isReached { return SharpitColor.signalRecovery }
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

    /// A race card's second line: its result once done, a word once past without one, else
    /// its day, format and place.
    static func raceCardLine(_ goal: V1Goal) -> String {
        switch goal.raceStatus {
        case .done?: doneLine(goal)
        case .awaitingResult?: "Ta course est passée · résultat à lier"
        default: raceLine(goal)
        }
    }

    /// « Terminée · 5:40:03 · −19:57 vs objectif »; the time against the aim only when it
    /// names one, « Terminée » alone without a linked time.
    static func doneLine(_ goal: V1Goal) -> String {
        let time = goal.result?.durationSec
        let delta = time.flatMap { seconds in
            RaceTime.targetSeconds(from: goal.targetPerformance).map { RaceDelta(seconds: seconds - $0).label }
        }
        return ["Terminée", time.map(RaceTime.clock), delta].compactMap { $0 }.joined(separator: " · ")
    }

    /// « 6:05 »: hours and minutes, rounded to the minute.
    static func hoursMinutes(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
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

private extension V1Goal {
    static let placeholders: [V1Goal] = [
        V1Goal(id: "skeleton-0", title: "Semi-marathon de printemps", kind: .race, targetDate: .now.addingTimeInterval(60 * 86_400)),
        V1Goal(id: "skeleton-1", title: "Poids de forme", kind: .metric, currentValue: 72, targetValue: 70, unit: "kg"),
    ]
}

/// A race past its day with no result: say so where the goals are read, and offer the two ways
/// out — link the session raced, or validate the race without one.
struct RaceAwaitingResultNotice: View {
    let goal: V1Goal
    let store: GoalStore
    @State private var isPicking = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Ta course est passée", systemImage: "flag.checkered")
            Text(goal.title)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            Text("Lie la séance de ta course pour garder ton temps, ou valide l'objectif tel quel.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            HStack(spacing: SharpitSpacing.sm) {
                Button("Lier ma séance", systemImage: "link") { isPicking = true }
                    .font(SharpitTypography.bodyEmphasis)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, SharpitSpacing.md)
                    .padding(.vertical, SharpitSpacing.xs)
                    .foregroundStyle(SharpitColor.primaryForeground)
                    .background(SharpitColor.primary, in: Capsule())
                Button("Valider l'objectif") {
                    Task {
                        isWorking = true
                        await store.toggleAchieved(goal)
                        isWorking = false
                    }
                }
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.primary)
            }
            .buttonStyle(.sharpitPressable)
            .disabled(isWorking)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .sheet(isPresented: $isPicking) {
            RaceResultPickerSheet(goal: goal, candidates: store.raceDayActivities(for: goal)) { activity in
                isPicking = false
                Task { await store.linkResult(activity, to: goal) }
            }
            .sharpitSheet()
        }
    }
}

/// « Lier ma séance »: the sessions of the race's day, the longest first; a tap links and closes.
private struct RaceResultPickerSheet: View {
    let goal: V1Goal
    let candidates: [V1ActivityListItem]
    let onPick: (V1ActivityListItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    SharpitStateMessage(
                        title: "Aucune séance ce jour-là",
                        symbol: "figure.run",
                        detail: "Synchronise ta montre, ou ouvre la séance de ta course pour la lier depuis son menu."
                    )
                } else {
                    List(candidates) { activity in
                        Button { onPick(activity) } label: { row(activity) }
                            .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Lier ma séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func row(_ activity: V1ActivityListItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(activity.title ?? activity.type.label)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            Text([ActivityFormat.dayLabel(for: activity.date), activity.duration.map { RaceTime.clock($0) }]
                .compactMap { $0 }
                .joined(separator: " · "))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
