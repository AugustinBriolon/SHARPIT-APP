import SwiftUI

struct MacroPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tokenProvider: () async throws -> String
    var onPlanChanged: () -> Void = {}

    @State private var plan: V1TrainingPlan?
    @State private var datedGoals: [V1Goal] = []
    @State private var selectedGoalId: String = ""
    @State private var isLoading = true
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingArchiveAlert = false

    private let trainingPlanClient = TrainingPlanClient()
    private let goalClient = GoalClient()

    var body: some View {
        NavigationStack {
            ZStack {
                SharpitCanvasBackground()

                if isLoading {
                    ProgressView("Chargement du plan…")
                        .tint(SharpitColor.primary)
                } else if let plan {
                    activePlanContent(plan)
                } else {
                    noPlanContent
                }
            }
            .navigationTitle("Plan macro")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.primary)
                }
            }
            .task { await loadInitialData() }
            .confirmationDialog(
                "Archiver ce plan macro ?",
                isPresented: $showingArchiveAlert,
                titleVisibility: .visible
            ) {
                Button("Archiver", role: .destructive) {
                    Task { await archiveCurrentPlan() }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les phases et charges cibles disparaissent de Plan. Les séances déjà posées au calendrier restent.")
            }
        }
        .sharpitSheet()
    }

    // MARK: - Active Plan View

    private func activePlanContent(_ plan: V1TrainingPlan) -> some View {
        let maxLoad = max(plan.weeks.map(\.targetLoad).max() ?? 1, 1)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                MacroPlanHero(plan: plan, range: dateRangeString(for: plan))

                ForEach(groupWeeksByPhase(plan.weeks), id: \.phase) { group in
                    VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                        SharpitCardHeader(
                            title: group.phase.label,
                            symbol: group.phase.symbolName,
                            subtitle: group.weeks.count == 1 ? "1 semaine" : "\(group.weeks.count) semaines",
                            showsChevron: false
                        )
                        SharpitInsetGroup {
                            ForEach(group.weeks) { week in
                                MacroWeekRowView(week: week, maxLoad: maxLoad)
                            }
                        }
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .sharpitSurface(.panel)
                }

                Text("Ensuite : « Remplir ma semaine » pose les séances, « Ajuster le planning » réarrange la charge.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.horizontal, SharpitSpacing.xxs)

                Button(role: .destructive) {
                    showingArchiveAlert = true
                } label: {
                    Label("Archiver ce plan macro", systemImage: "archivebox")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.destructive)
                        .frame(maxWidth: .infinity, minHeight: SharpitSpacing.controlHeight)
                        .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
    }

    // MARK: - No Plan View

    private var noPlanContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    SharpitCardHeader(
                        title: "Définir un plan macro",
                        symbol: "calendar.badge.clock",
                        showsChevron: false
                    )
                    Text("Une course datée sert de jalon. Le plan macro calcule les phases et la charge de chaque semaine jusqu'à elle, sans poser les séances. Les courses B et C avant elle deviennent des étapes.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)

                if datedGoals.isEmpty {
                    SharpitStateMessage(
                        title: "Aucun objectif daté à venir",
                        symbol: "flag.checkered",
                        detail: "Ajoute une course dans Objectifs pour générer un plan macro."
                    )
                    .frame(minHeight: 240)
                } else {
                    VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                        SharpitCardHeader(title: "Objectif ciblé", symbol: "flag.checkered", showsChevron: false)
                        SharpitInsetGroup {
                            ForEach(datedGoals) { goal in
                                MacroGoalChoiceRow(
                                    goal: goal,
                                    isSelected: goal.id == selectedGoalId
                                ) { selectedGoalId = goal.id }
                            }
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.destructive)
                        }
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .sharpitSurface(.panel)
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            if !datedGoals.isEmpty {
                SharpitPrimaryButton(
                    title: isGenerating ? "Génération en cours…" : "Générer le plan macro",
                    trailingSymbol: isGenerating ? nil : "sparkles",
                    isBusy: isGenerating
                ) {
                    Task { await generateNewPlan() }
                }
                .disabled(isGenerating || selectedGoalId.isEmpty)
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.bottom, SharpitSpacing.xs)
            }
        }
    }

    // MARK: - Actions

    private func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        do {
            let token = try await tokenProvider()
            async let planTask = trainingPlanClient.fetchActivePlan(token: token)
            async let goalsTask = goalClient.goals(token: token)

            let (fetchedPlan, fetchedGoals) = try await (planTask, goalsTask)
            plan = fetchedPlan

            let now = Date()
            let filteredGoals = fetchedGoals.filter { goal in
                guard !goal.achieved, let targetDate = goal.targetDate else { return false }
                return targetDate >= now
            }
            datedGoals = filteredGoals
            if let first = filteredGoals.first {
                selectedGoalId = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func generateNewPlan() async {
        guard !selectedGoalId.isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        do {
            let token = try await tokenProvider()
            let newPlan = try await trainingPlanClient.generatePlan(goalId: selectedGoalId, token: token)
            plan = newPlan
            onPlanChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    /// Gone from the sheet on the confirm, archived behind (retried); a refusal for good puts the
    /// plan back and is said in the app's toast.
    private func archiveCurrentPlan() async {
        guard let currentPlan = plan else { return }
        plan = nil
        do {
            try await SharpitRetry.run { [trainingPlanClient, tokenProvider] in
                try await trainingPlanClient.archivePlan(id: currentPlan.id, token: try await tokenProvider())
            }
            onPlanChanged()
        } catch {
            if plan == nil { plan = currentPlan }
            SharpitWriteFailures.shared.report("Le plan n’a pas pu être archivé. Réessaie dans un instant.")
        }
    }


    private func dateRangeString(for plan: V1TrainingPlan) -> String? {
        guard let first = plan.weeks.first, let last = plan.weeks.last else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        let start = f.string(from: first.weekStart)
        f.dateFormat = "d MMM yyyy"
        let end = f.string(from: last.weekStart)
        return "\(start) - \(end)"
    }

    private func groupWeeksByPhase(_ weeks: [V1PlanWeek]) -> [(phase: V1PlanPhase, weeks: [V1PlanWeek])] {
        var groups: [(phase: V1PlanPhase, weeks: [V1PlanWeek])] = []
        for week in weeks {
            if let last = groups.last, last.phase == week.phase {
                groups[groups.count - 1].weeks.append(week)
            } else {
                groups.append((phase: week.phase, weeks: [week]))
            }
        }
        return groups
    }
}

// MARK: - MacroPlanHero

/// The sheet's one ink card: how long, when, the phases in a rail with the current one lit.
private struct MacroPlanHero: View {
    let plan: V1TrainingPlan
    let range: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(SharpitColor.highlightForeground)
                    .frame(width: SharpitTokens.tileSize, height: SharpitTokens.tileSize)
                    .sharpitConcentricBackground(SharpitColor.highlight, minimum: SharpitRadius.tile)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(plan.weeks.count) semaines")
                        .font(SharpitTypography.sectionTitle)
                        .tracking(SharpitTypography.sectionTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    if let range {
                        Text(range)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
            }

            MacroPhaseRailView(plan: plan)

            if let summary = plan.summary, !summary.isEmpty {
                Text(summary)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .sharpitSurface(.ink)
    }
}

// MARK: - MacroGoalChoiceRow

/// A dated goal to build toward: its name, when, its priority; a check on the one chosen.
private struct MacroGoalChoiceRow: View {
    let goal: V1Goal
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                    if let date = goal.targetDate {
                        Text(date.sharpitFormatted(.dateTime.day().month(.abbreviated).year()))
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                Spacer(minLength: SharpitSpacing.xs)
                if let priority = goal.priority {
                    SharpitPill("Course \(priority.rawValue)", style: priority == .a ? .lime : .neutral)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.mutedForeground.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, SharpitSpacing.rowPaddingX)
            .frame(minHeight: SharpitSpacing.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - MacroPhaseRailView

private struct MacroPhaseRailView: View {
    let plan: V1TrainingPlan

    var body: some View {
        let runs = computePhaseRuns(plan.weeks)
        HStack(spacing: 4) {
            ForEach(runs, id: \.phase) { run in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(run.isCurrent ? SharpitColor.highlight : SharpitColor.track)
                        .frame(height: 6)
                    Text(run.phase.shortLabel)
                        .font(SharpitTypography.system(size: 12, weight: run.isCurrent ? .bold : .medium, relativeTo: .caption))
                        .foregroundStyle(run.isCurrent ? SharpitColor.foreground : SharpitColor.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                // Each phase as wide as its weeks.
                .frame(maxWidth: .infinity)
                .layoutPriority(Double(run.weeks))
            }
        }
    }

    private func computePhaseRuns(_ weeks: [V1PlanWeek]) -> [(phase: V1PlanPhase, weeks: Int, isCurrent: Bool)] {
        var runs: [(phase: V1PlanPhase, weeks: Int)] = []
        for week in weeks {
            if runs.last?.phase == week.phase {
                runs[runs.count - 1].weeks += 1
            } else {
                runs.append((week.phase, 1))
            }
        }

        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let currentMonday = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        let currentPhase = weeks.first { week in
            let weekStart = cal.dateInterval(of: .weekOfYear, for: week.weekStart)?.start ?? week.weekStart
            return abs(weekStart.timeIntervalSince(currentMonday)) < 86400
        }?.phase

        return runs.map { run in
            (phase: run.phase, weeks: run.weeks, isCurrent: run.phase == currentPhase)
        }
    }
}

// MARK: - MacroWeekRowView

/// A week: its date and what it works, the target load as a figure and a bar against the
/// plan's heaviest week — lime for this week.
private struct MacroWeekRowView: View {
    let week: V1PlanWeek
    let maxLoad: Double

    var body: some View {
        let isCurrent = isCurrentWeek(week.weekStart)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text(week.weekStart.sharpitFormatted(.dateTime.day().month(.abbreviated)))
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                if isCurrent {
                    SharpitPill("Cette semaine", style: .lime)
                }
                Spacer(minLength: SharpitSpacing.xs)
                SharpitRowFigure(value: "\(Int(week.targetLoad))", unit: "TSS")
            }
            if let quality = WeekQualityLabel.from(focus: week.focus, phase: week.phase, isDeload: week.isDeload) {
                Text(quality)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }
            SharpitBarTrack(
                fraction: week.targetLoad / maxLoad,
                tone: isCurrent ? SharpitColor.highlight : SharpitColor.foreground
            )
            .frame(height: 4)
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    private func isCurrentWeek(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let currentInterval = cal.dateInterval(of: .weekOfYear, for: .now)
        let weekInterval = cal.dateInterval(of: .weekOfYear, for: date)
        guard let c = currentInterval, let w = weekInterval else { return false }
        return abs(c.start.timeIntervalSince(w.start)) < 86400
    }
}

/// Athlete-facing week quality derived from focus/phase (mirrors ADR-083 / week-quality.ts).
private enum WeekQualityLabel {
    static func from(focus: String?, phase: V1PlanPhase, isDeload: Bool) -> String? {
        if isDeload { return "Semaine facile" }
        let haystack = [focus, phase.rawValue].compactMap { $0 }.joined(separator: " ").lowercased()
        if haystack.range(of: "reprise|retour|return", options: .regularExpression) != nil {
            return "Reprise"
        }
        if haystack.range(of: "deload|récup|recup|facile|alléger|alleger", options: .regularExpression) != nil {
            return "Semaine facile"
        }
        if haystack.range(of: "affût|affut|taper", options: .regularExpression) != nil {
            return "Affûtage"
        }
        if haystack.range(of: "force|côte|cote|hill|ppg|renfo", options: .regularExpression) != nil {
            return "Force / côtes"
        }
        if haystack.range(of: "vma|vo2", options: .regularExpression) != nil {
            return "VMA / VO2"
        }
        if haystack.range(of: "seuil|tempo|lt2|sweet", options: .regularExpression) != nil {
            return "Seuil"
        }
        if haystack.range(of: "allure|spécific|specific|simulation|race", options: .regularExpression) != nil {
            return "Allure spécifique"
        }
        if haystack.range(of: "aérob|aerob|zone.?2|fondamentale|endurance|volume", options: .regularExpression) != nil {
            return "Volume aérobie"
        }
        switch phase {
        case .base: return "Volume aérobie"
        case .build: return "Seuil"
        case .peak: return "Allure spécifique"
        case .taper: return "Affûtage"
        case .race: return "Course"
        }
    }
}
