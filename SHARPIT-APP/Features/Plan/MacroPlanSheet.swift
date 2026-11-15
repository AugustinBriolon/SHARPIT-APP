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
                String(localized: "Archiver ce plan macro ?"),
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
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                MacroPlanHero(plan: plan, range: dateRangeString(for: plan))

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Les semaines")
                            .font(SharpitTypography.sectionTitle)
                            .foregroundStyle(SharpitColor.foreground)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: SharpitSpacing.xs)
                        Text("charge prévue")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                    }
                    .padding(.bottom, SharpitSpacing.xs)
                    ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { index, week in
                        MacroWeekRowView(week: week)
                        if index < plan.weeks.count - 1 { CliniqueDivider() }
                    }
                }

                Text("Ensuite : « Remplir ma semaine » pose les séances, « Ajuster le planning » réarrange la charge.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .padding(.horizontal, SharpitSpacing.xxs)

                Button("Archiver ce plan macro") { showingArchiveAlert = true }
                    .buttonStyle(CliniqueButtonStyle(kind: .outline))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, SharpitSpacing.md)
        }
    }

    // MARK: - No Plan View

    private var noPlanContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    SharpitCardHeader(
                        title: String(localized: "Définir un plan macro"),
                        symbol: "calendar.badge.clock",
                        showsChevron: false
                    )
                    Text("Une course datée sert de jalon. Le plan macro calcule les phases et la charge de chaque semaine jusqu'à elle, sans poser les séances. Les courses B et C avant elle deviennent des étapes.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if datedGoals.isEmpty {
                    SharpitStateMessage(
                        title: String(localized: "Aucun objectif daté à venir"),
                        symbol: "flag.checkered",
                        detail: String(localized: "Ajoute une course dans Objectifs pour générer un plan macro.")
                    )
                    .frame(minHeight: 240)
                } else {
                    VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                        SharpitCardHeader(title: String(localized: "Objectif ciblé"), symbol: "flag.checkered", showsChevron: false)
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
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            if !datedGoals.isEmpty {
                SharpitPrimaryButton(
                    title: isGenerating ? String(localized: "Génération en cours…") : String(localized: "Générer le plan macro"),
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
            SharpitWriteFailures.shared.report(String(localized: "Le plan n’a pas pu être archivé. Réessaie dans un instant."))
        }
    }


    private func dateRangeString(for plan: V1TrainingPlan) -> String? {
        guard let first = plan.weeks.first, let last = plan.weeks.last else { return nil }
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateFormat = "d MMM"
        let start = f.string(from: first.weekStart)
        f.dateFormat = "d MMM yyyy"
        let end = f.string(from: last.weekStart)
        return "\(start) - \(end)"
    }

}

// MARK: - MacroPlanHero

/// The plan's head, on the sheet: how long and when, then the phases as a rail — each as wide
/// as its weeks, in its hue, the current one ringed in ink.
private struct MacroPlanHero: View {
    let plan: V1TrainingPlan
    let range: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                if let range {
                    Text(range)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
                Text("\(plan.weeks.count) semaines")
                    .font(SharpitTypography.system(size: 22, weight: .semibold, relativeTo: .title2, digits: true))
                    .tracking(-0.4)
                    .foregroundStyle(SharpitColor.foreground)
            }

            MacroPhaseRailView(plan: plan)

            if let summary = plan.summary, !summary.isEmpty {
                Text(summary)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
                Spacer(minLength: SharpitSpacing.xs)
                if let priority = goal.priority {
                    SharpitPill(String(localized: "Course \(priority.rawValue)"), style: priority == .a ? .lime : .neutral)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.slate.opacity(0.4))
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
        HStack(spacing: 6) {
            ForEach(runs, id: \.phase) { run in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(MacroPlanReadout.hue(run.phase))
                        .frame(height: 10)
                        .overlay {
                            if run.isCurrent {
                                Capsule().strokeBorder(SharpitColor.foreground, lineWidth: 2).padding(-3)
                            }
                        }
                    Text(run.phase.shortLabel)
                        .font(SharpitTypography.system(size: 12, weight: run.isCurrent ? .semibold : .regular, relativeTo: .caption))
                        .foregroundStyle(run.isCurrent ? SharpitColor.foreground : SharpitColor.slate)
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

/// A week as a line of the table: its Monday, what it works, the load it aims for — this week
/// in bold.
private struct MacroWeekRowView: View {
    let week: V1PlanWeek

    var body: some View {
        let isCurrent = isCurrentWeek(week.weekStart)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(week.weekStart.sharpitFormatted(.dateTime.day().month(.abbreviated)))
                .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                .foregroundStyle(SharpitColor.slate)
                .frame(width: 70, alignment: .leading)
            Text(WeekQualityLabel.from(focus: week.focus, phase: week.phase, isDeload: week.isDeload) ?? week.phase.label)
                .font(SharpitTypography.system(size: 16, weight: isCurrent ? .semibold : .regular, relativeTo: .callout))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)
            Spacer(minLength: SharpitSpacing.xs)
            Text("\(Int(week.targetLoad))")
                .font(SharpitTypography.system(size: 15, weight: isCurrent ? .semibold : .regular, relativeTo: .subheadline, digits: true))
                .foregroundStyle(SharpitColor.foreground)
        }
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
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

/// The macro plan's marks.
enum MacroPlanReadout {
    /// A phase's hue on the rail: the season cools into volume, greens into the specific work,
    /// warms into the taper — chart marks, never text.
    static func hue(_ phase: V1PlanPhase) -> Color {
        switch phase {
        case .base: SharpitColor.pillarSleep
        case .build: SharpitColor.pillarCoach
        case .peak: SharpitColor.pillarRecovery
        case .taper, .race: SharpitColor.pillarNutrition
        }
    }
}

/// Athlete-facing week quality derived from focus/phase (mirrors ADR-083 / week-quality.ts).
private enum WeekQualityLabel {
    static func from(focus: String?, phase: V1PlanPhase, isDeload: Bool) -> String? {
        if isDeload { return String(localized: "Semaine facile") }
        let haystack = [focus, phase.rawValue].compactMap { $0 }.joined(separator: " ").lowercased()
        if haystack.range(of: "reprise|retour|return", options: .regularExpression) != nil {
            return String(localized: "Reprise")
        }
        if haystack.range(of: "deload|récup|recup|recovery|facile|easy|alléger|alleger|lighter", options: .regularExpression) != nil {
            return String(localized: "Semaine facile")
        }
        if haystack.range(of: "affût|affut|taper", options: .regularExpression) != nil {
            return String(localized: "Affûtage")
        }
        if haystack.range(of: "force|strength|côte|cote|hill|ppg|renfo", options: .regularExpression) != nil {
            return String(localized: "Force / côtes")
        }
        if haystack.range(of: "vma|vo2", options: .regularExpression) != nil {
            return "VMA / VO2"
        }
        if haystack.range(of: "seuil|tempo|lt2|sweet", options: .regularExpression) != nil {
            return String(localized: "Seuil")
        }
        if haystack.range(of: "allure|spécific|specific|simulation|race", options: .regularExpression) != nil {
            return String(localized: "Allure spécifique")
        }
        if haystack.range(of: "aérob|aerob|zone.?2|fondamentale|base|endurance|volume", options: .regularExpression) != nil {
            return String(localized: "Volume aérobie")
        }
        switch phase {
        case .base: return String(localized: "Volume aérobie")
        case .build: return String(localized: "Seuil")
        case .peak: return String(localized: "Allure spécifique")
        case .taper: return String(localized: "Affûtage")
        case .race: return String(localized: "Course")
        }
    }
}
