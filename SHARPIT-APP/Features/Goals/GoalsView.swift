import StoreKit
import SwiftData
import SwiftUI
import TipKit

/// Plan → Objectifs: the races and figures the season is built toward.
///
/// One list, no tabs: the next race leads on the ink plate, the races leading to it on the season
/// timeline, then the goals in progress, then —
/// further down, only when there are any — the ones reached. A goal and a new goal open as pages
/// in this stack. The store is Plan's, so reopening shows the goals at once and refreshes them
/// quietly.
struct GoalsView: View {
    @State private var store: GoalStore
    @State private var hasAppeared = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview

    init(store: GoalStore) {
        _store = State(initialValue: store)
    }

    /// Neither on the plate nor on the season timeline.
    private var inProgress: [V1Goal] {
        let shown = Set([store.nextRace?.id].compactMap { $0 } + (store.seasonTimeline?.steps.map(\.id) ?? []))
        return store.activeGoalsOrdered.filter { !shown.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let next = store.nextRace {
                    NavigationLink(value: GoalRoute.detail(next)) {
                        NextRaceCard(goal: next)
                    }
                    .buttonStyle(.sharpitPressable)
                    .revealed(hasAppeared, index: 0)
                } else if !(store.goals.isEmpty && store.isLoading) {
                    Text("Objectifs")
                        .font(SharpitTypography.system(size: 32, weight: .semibold, relativeTo: .largeTitle))
                        .tracking(-0.6)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                }

                if let timeline = store.seasonTimeline, !timeline.steps.isEmpty {
                    SeasonTimelineView(timeline: timeline)
                        .revealed(hasAppeared, index: 1)
                }

                ForEach(store.seasonConflicts) { conflict in
                    SeasonConflictNotice(conflict: conflict, store: store)
                        .revealed(hasAppeared, index: 1)
                }

                ForEach(store.racesAwaitingResult) { race in
                    RaceAwaitingResultNotice(goal: race, store: store)
                        .revealed(hasAppeared, index: 0)
                }

                if store.goals.isEmpty && store.showsSkeleton {
                    // The page's own shape while the goals load: the race plate, then each section.
                    VStack(alignment: .leading, spacing: 26) {
                        NextRaceCard(goal: V1Goal.placeholderRace)
                        skeletonSection(String(localized: "En cours"), goals: V1Goal.placeholders)
                        skeletonSection(String(localized: "Atteints"), goals: [V1Goal.placeholderReached])
                    }
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Chargement des objectifs")
                } else if store.activeGoals.isEmpty {
                    emptyState
                        .revealed(hasAppeared, index: 1)
                } else if !inProgress.isEmpty {
                    TipView(GoalReachedTip())
                        .tipBackground(SharpitColor.tile)
                        .tint(SharpitColor.foreground)
                    goalList(title: String(localized: "En cours"), goals: inProgress, startIndex: 1)
                }

                if !store.completedGoals.isEmpty {
                    goalList(title: String(localized: "Atteints"), goals: store.completedGoals, startIndex: inProgress.count + 2)
                        .opacity(0.8)
                }

                if !store.recentAchievements.isEmpty {
                    achievementList
                        .revealed(hasAppeared, index: inProgress.count + store.completedGoals.count + 3)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(SharpitMotion.reveal, value: store.goals)
        }
        .scrollIndicators(.hidden)
        .cliniqueSheet(wash: .coach, height: 240)
        .navigationTitle("Objectifs")
        .navigationBarTitleDisplayMode(.inline)
        // The bar carries the way back and « Nouvel objectif »; the race ahead opens the page.
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: GoalRoute.create) {
                    Text("Nouvel objectif")
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                }
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
        .task { await store.load(keptIn: modelContext) }
        .task { await GoalReachedTip.goalsOpened.donate() }
        // A goal reached, from this list or from its page pushed in this stack.
        .onChange(of: store.lastReachedAt) { _, reached in
            if reached != nil { ReviewPrompt.askAfterWin(requestReview) }
        }
        .refreshable { await store.load() }
        .onAppear { hasAppeared = true }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
            .accessibilityAddTraits(.isHeader)
    }

    private func skeletonSection(_ title: String, goals: [V1Goal]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // The sections are known before the goals are: their names are never redacted.
            sectionTitle(title).unredacted()
            ForEach(goals) { goal in
                CliniqueDivider()
                GoalCard(goal: goal)
            }
        }
    }

    private func goalList(title: String, goals: [V1Goal], startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(title)
            LazyVStack(spacing: 0) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                    CliniqueDivider()
                    NavigationLink(value: GoalRoute.detail(goal)) {
                        GoalCard(goal: goal)
                    }
                    .buttonStyle(.sharpitPressable)
                    .contextMenu {
                        Button {
                            Task { await store.toggleAchieved(goal) }
                        } label: {
                            Label(goal.achieved ? String(localized: "Remettre en cours") : String(localized: "Marquer comme atteint"),
                                  systemImage: goal.achieved ? "arrow.uturn.backward" : "checkmark.circle")
                        }
                        SharpitDeleteMenuButton { Task { await store.delete(id: goal.id) } }
                    }
                    .revealed(hasAppeared, index: startIndex + index)
                }
            }
        }
    }

    /// « Réalisations récentes »: each time a goal was reached, as the web lists them under its
    /// goals — the figure, the period, the day, and the session that did it when there is one.
    private var achievementList: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(String(localized: "Réalisations récentes"))
            LazyVStack(spacing: 0) {
                ForEach(store.recentAchievements) { achievement in
                    if achievement.id != store.recentAchievements.first?.id { CliniqueDivider() }
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Aucun objectif en cours")
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
            Text("Ajoute une course ou une cible chiffrée : le plan s'organise autour.")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: GoalRoute.create) { Text("Nouvel objectif") }
                .buttonStyle(CliniqueButtonStyle(kind: .primary))
        }
        .cliniqueCard()
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

/// The race ahead, opening the page: how far it is, what and when, the server's projected finish
/// against the aim, the legs as one bar, and how far to trust it.
private struct NextRaceCard: View {
    let goal: V1Goal

    private var readout: RaceProjectionReadout? { goal.projection.map { RaceProjectionReadout($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(GoalsReadout.lead(goal))
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                Text(GoalsReadout.title(goal))
                    .font(SharpitTypography.system(size: 28, weight: .semibold, relativeTo: .title, digits: true))
                    .tracking(-0.5)
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.leading)
            }
            if let readout {
                let finish = Text(GoalsReadout.spaced(readout.finishLabel))
                    .font(SharpitTypography.system(size: 46, weight: .semibold, relativeTo: .largeTitle, digits: true))
                    .tracking(-1.2)
                    .foregroundStyle(SharpitColor.foreground)
                let aim = Text([String(localized: "projeté"), goal.targetPerformance.flatMap { $0.isEmpty ? nil : String(localized: "objectif \($0)") }].compactMap(\.self).joined(separator: " · "))
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                // Beside the time while the aim fits on its line; under it when the athlete wrote a long one.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) { finish; aim }
                    VStack(alignment: .leading, spacing: 4) { finish; aim }
                }
                let legs = readout.legs
                if !legs.isEmpty {
                    GeometryReader { geo in
                        HStack(spacing: 3) {
                            ForEach(legs) { leg in
                                Capsule().fill(GoalsReadout.hue(leg.segment.sport))
                                    .frame(width: max(4, (geo.size.width - CGFloat(legs.count - 1) * 3) * leg.segment.fraction))
                            }
                        }
                    }
                    .frame(height: 10)
                    .accessibilityHidden(true)
                    HStack(alignment: .top, spacing: SharpitSpacing.md) {
                        ForEach(legs.filter { $0.segment.sport != nil }) { leg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(leg.segment.label)
                                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                                    .foregroundStyle(SharpitColor.slate)
                                Text(GoalsReadout.spaced(GoalAnalyticsEngine.formatDuration(leg.segment.durationSec)))
                                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline, digits: true))
                                    .foregroundStyle(SharpitColor.foreground)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                HStack(spacing: 10) {
                    if let confidence = readout.confidenceLabel {
                        CliniqueStatusPill(confidence.capitalizedFirst, status: goal.projection?.confidence == .low ? .watch : .good)
                    }
                    if let line = readout.trajectoryLine ?? readout.delta?.label {
                        Text(line)
                            .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
            } else {
                Text(GoalFormat.raceLine(goal))
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// How Objectifs words the race ahead.
enum GoalsReadout {
    /// « 2h28 » → « 2 h 28 », « 27min » → « 27 min »: the server's compact times, set as the page reads them.
    static func spaced(_ time: String) -> String {
        time.replacing(/(\d)(h|min)(\d?)/) { match in
            "\(match.1) \(match.2)\(match.3.isEmpty ? "" : " \(match.3)")"
        }
    }

    /// « Prochaine course · dans 37 jours », « … · aujourd'hui ».
    static func lead(_ goal: V1Goal) -> String {
        let head = String(localized: "Prochaine course")
        guard let days = goal.daysRemaining, days >= 0 else { return head }
        switch days {
        case 0: return String(localized: "\(head) · aujourd'hui")
        case 1: return String(localized: "\(head) · demain")
        default: return String(localized: "\(head) · dans \(days) jours")
        }
    }

    /// A goal's month at the end of its line; with its year when that is not this one, so a
    /// race of last October is not read as the coming one.
    static func rowDate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.sharpitFormatted(.dateTime.month(.wide))
            : date.sharpitFormatted(.dateTime.month(.abbreviated).year())
    }

    /// « Triathlon M, 21 décembre »; the name alone without a day.
    static func title(_ goal: V1Goal) -> String {
        guard let day = goal.targetDate?.sharpitFormatted(.dateTime.day().month(.wide)) else { return goal.title }
        return "\(goal.title), \(day)"
    }

    /// A leg's hue on the bar: a data mark, so the pillars' hues; a transition stays quiet.
    static func hue(_ sport: V1ActivityType?) -> Color {
        switch sport {
        case .swim?: SharpitColor.pillarSleep
        case .bike?: SharpitColor.pillarRecovery
        case .run?: SharpitColor.pillarNutrition
        default: SharpitColor.outline
        }
    }
}

/// One goal as a line: where it stands as a ring, what it is, and its day at the trailing edge.
private struct GoalCard: View {
    let goal: V1Goal

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if goal.isReached {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(SharpitColor.pillarRecovery)
                    .frame(width: 44)
                    .accessibilityHidden(true)
            } else {
                CliniqueRing(pillar: goal.kind == .race ? .coach : .recovery, fraction: goal.kind == .metric ? goal.progressFraction : nil, symbol: goal.kind == .race ? "flag" : "arrow.up.right", size: 44, animated: false)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(goal.kind == .race ? GoalFormat.raceCardLine(goal) : GoalFormat.metricLine(goal))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: SharpitSpacing.xs)
            if !goal.isReached, let date = goal.targetDate {
                Text(GoalsReadout.rowDate(date))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// One time a goal was reached: the goal, then what, when and how, in the web's words.
private struct GoalAchievementRow: View {
    let achievement: V1GoalAchievement
    let opensSession: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(SharpitColor.pillarRecovery)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(achievement.goal.title)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(GoalAchievementReadout.line(achievement))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: SharpitSpacing.xs)
            if opensSession {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
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
                SharpitEyebrow(goal.isReached ? String(localized: "Course courue") : (goal.phaseLabel ?? String(localized: "Course")), systemImage: "flag.checkered")
                Spacer(minLength: 0)
                if let role = goal.role {
                    GoalRoleChip(role: role)
                }
            }
            Text(goal.title)
                .font(SharpitTypography.system(size: 28, weight: .semibold, relativeTo: .title))
                .tracking(-0.5)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if goal.isReached, goal.result?.durationSec != nil {
                Text(GoalFormat.doneLine(goal))
                    .font(SharpitTypography.verdict)
                    .tracking(SharpitTypography.verdictTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(goal.isReached || goal.daysRemaining == nil
                ? GoalFormat.raceLine(goal)
                : "\(GoalFormat.raceLine(goal)) · \(GoalFormat.daysValue(goal)) \(GoalFormat.daysUnit(goal))")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline, digits: true))
                .foregroundStyle(SharpitColor.slate)
            if !goal.isReached, let consequence = goal.roleConsequence {
                Text(consequence)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            if let performance = goal.targetPerformance, !performance.isEmpty {
                Text("Objectif chrono · \(performance)")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metric: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitEyebrow(goal.achieved ? String(localized: "Atteint") : String(localized: "Objectif chiffré"), systemImage: "gauge.with.dots.needle.67percent")
                Text(goal.title)
                    .font(SharpitTypography.pageTitle)
                    .tracking(SharpitTypography.pageTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text(GoalFormat.metricLine(goal))
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.slate)
                    .monospacedDigit()
                if let date = goal.targetDate {
                    Text("Échéance · \(date.sharpitFormatted(.dateTime.day().month(.wide).year()))")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            Spacer(minLength: 0)
            if let progress = goal.progressFraction {
                ZStack {
                    SharpitScoreRing(fraction: progress, tone: goal.achieved ? SharpitColor.statusGoodMark : SharpitColor.primary, lineWidth: 6)
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(SharpitTypography.data)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                }
                .frame(width: 88, height: 88)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The race's role on the ink plate: the principal in the highlight, the others quiet.
private struct GoalRoleChip: View {
    let role: GoalRole

    var body: some View {
        Text(role.label)
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .foregroundStyle(role == .primary ? SharpitColor.primaryForeground : SharpitColor.foreground)
            .padding(.horizontal, SharpitSpacing.xs)
            .padding(.vertical, 3)
            .background(
                role == .primary ? SharpitColor.primary : SharpitColor.foreground.opacity(0.16),
                in: Capsule()
            )
    }
}

// MARK: - Season

/// The races before the principal, soonest first, on a rail that ends on the principal: each
/// its day, what it is, how far, its role toward the principal and the gap to what follows.
private struct SeasonTimelineView: View {
    let timeline: GoalSeason.Timeline

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(String(localized: "En route · \(timeline.steps.count) \(timeline.steps.count == 1 ? "étape" : "étapes")"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(timeline.steps) { step in
                    NavigationLink(value: GoalRoute.detail(step.goal)) {
                        stepRow(step)
                    }
                    .buttonStyle(.sharpitPressable)
                }
                principalRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stepRow(_ step: GoalSeason.Step) -> some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            rail(node: Circle().strokeBorder(SharpitColor.primary, lineWidth: 2), continues: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.day(step.goal))
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .monospacedDigit()
                Text(step.goal.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.leading)
                Text(Self.meta(step.goal))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                Text(step.goal.role == .training ? GoalRole.training.label : "\(GoalRole.step.label) vers \(timeline.principal.title)")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.primary)
                    .multilineTextAlignment(.leading)
                Text("puis \(GoalSeason.span(days: step.daysToNext))")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate.opacity(0.8))
                    .padding(.top, SharpitSpacing.xs)
                    .padding(.bottom, SharpitSpacing.sm)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SharpitColor.slate.opacity(0.5))
                .padding(.top, SharpitSpacing.sm)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var principalRow: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            rail(node: Circle().fill(SharpitColor.statusGoodMark), continues: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.day(timeline.principal))
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .monospacedDigit()
                Text(timeline.principal.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text([GoalRole.primary.label, Self.meta(timeline.principal)].joined(separator: " · "))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rail(node: some View, continues: Bool) -> some View {
        VStack(spacing: 0) {
            node.frame(width: 11, height: 11).padding(.top, 3)
            if continues {
                Rectangle()
                    .fill(SharpitColor.slate.opacity(0.25))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 11)
    }

    /// « 12 avr. 2027 »
    private static func day(_ goal: V1Goal) -> String {
        goal.targetDate?.sharpitFormatted(.dateTime.day().month(.abbreviated).year()) ?? ""
    }

    /// « Triathlon L · dans 6 mois »
    private static func meta(_ goal: V1Goal) -> String {
        [goal.raceFormat, goal.daysRemaining.map(GoalSeason.until(days:))]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Two principals in one season, said quietly, with the one change that settles it.
private struct SeasonConflictNotice: View {
    let conflict: GoalSeason.Conflict
    let store: GoalStore

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(String(localized: "Deux objectifs principaux"), systemImage: "flag.2.crossed")
            Text("\(conflict.kept.title) et \(conflict.demoted.title) sont à moins de six mois l’une de l’autre : le plan ne s’affûte vraiment que pour une.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
            Button("Passer \(conflict.demoted.title) en course étape") {
                store.setPriority(.b, of: conflict.demoted)
            }
            .font(SharpitTypography.bodyEmphasis)
            .foregroundStyle(SharpitColor.primary)
            .buttonStyle(.sharpitPressable)
            .padding(.top, SharpitSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        return days == 0 ? String(localized: "Jour de course") : String(localized: "Épreuve passée")
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
        case .awaitingResult?: String(localized: "Ta course est passée · résultat à lier")
        default: [goal.role?.label, raceLine(goal)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// « Terminée · 5:40:03 · −19:57 vs objectif »; the time against the aim only when it
    /// names one, « Terminée » alone without a linked time.
    static func doneLine(_ goal: V1Goal) -> String {
        let time = goal.result?.durationSec
        let delta = time.flatMap { seconds in
            RaceTime.targetSeconds(from: goal.targetPerformance).map { RaceDelta(seconds: seconds - $0).label }
        }
        return [String(localized: "Terminée"), time.map(RaceTime.clock), delta].compactMap { $0 }.joined(separator: " · ")
    }

    /// « 265 / 280 W » or « Cible 280 W ».
    static func metricLine(_ goal: V1Goal) -> String {
        let unit = goal.unit.map { " \($0)" } ?? ""
        switch (goal.currentValue, goal.targetValue) {
        case let (current?, target?): return "\(number(current)) / \(number(target))\(unit)"
        case let (nil, target?): return String(localized: "Cible \(number(target))\(unit)")
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
        V1Goal(id: "skeleton-0", title: String(localized: "Semi-marathon de printemps"), kind: .race, targetDate: .now.addingTimeInterval(60 * 86_400)),
        V1Goal(id: "skeleton-1", title: String(localized: "Poids de forme"), kind: .metric, currentValue: 72, targetValue: 70, unit: "kg"),
    ]
    /// With a projection, so the skeleton's race plate is as tall as the real one: the finish
    /// read big, the legs' bar and times, the reliability pill.
    static let placeholderRace: V1Goal = {
        var race = V1Goal(
            id: "skeleton-race", title: String(localized: "Triathlon de la saison"), kind: .race, targetDate: .now.addingTimeInterval(90 * 86_400)
        )
        race.projection = V1RaceProjection(
            finishSec: 20_400, lowSec: 20_000, highSec: 20_900, deltaSec: -300,
            legs: [.init(kind: .swim, sec: 2_100), .init(kind: .bike, sec: 10_800), .init(kind: .run, sec: 7_000)],
            confidence: .medium
        )
        return race
    }()
    static let placeholderReached = V1Goal(id: "skeleton-reached", title: String(localized: "Course de l'an dernier"), kind: .race, achieved: true)
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
            SharpitEyebrow(String(localized: "Ta course est passée"), systemImage: "flag.checkered")
            Text(goal.title)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            Text("Lie la séance de ta course pour garder ton temps, ou valide l'objectif tel quel.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        title: String(localized: "Aucune séance ce jour-là"),
                        symbol: "figure.run",
                        detail: String(localized: "Synchronise ta montre, ou ouvre la séance de ta course pour la lier depuis son menu.")
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
                .foregroundStyle(SharpitColor.slate)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
