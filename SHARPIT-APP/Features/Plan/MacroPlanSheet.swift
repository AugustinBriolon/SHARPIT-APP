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
    @State private var isArchiving = false
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
    }

    // MARK: - Active Plan View

    private func activePlanContent(_ plan: V1TrainingPlan) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                // Summary Card
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(plan.weeks.count) semaines")
                            .font(SharpitTypography.cardTitle)
                            .foregroundStyle(SharpitColor.foreground)

                        Spacer()

                        if let range = dateRangeString(for: plan) {
                            Text(range)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }

                    MacroPhaseRailView(plan: plan)
                        .padding(.top, SharpitSpacing.xs)

                    if let summary = plan.summary, !summary.isEmpty {
                        Text(summary)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineSpacing(3)
                            .padding(.top, SharpitSpacing.xxs)
                    }
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
                .sharpitCardSpecularBorder()

                // Weeks by Phase
                let grouped = groupWeeksByPhase(plan.weeks)
                ForEach(grouped, id: \.phase) { group in
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        HStack {
                            Text(group.phase.label.uppercased())
                                .font(SharpitTypography.label)
                                .tracking(SharpitTypography.labelTracking)
                                .foregroundStyle(SharpitColor.mutedForeground)

                            Text("· \(group.weeks.count) sem.")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.7))
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(group.weeks.enumerated()), id: \.element.id) { index, week in
                                MacroWeekRowView(week: week)

                                if index < group.weeks.count - 1 {
                                    Divider()
                                        .background(SharpitColor.border.opacity(0.35))
                                }
                            }
                        }
                        .padding(.horizontal, SharpitSpacing.cardPadding)
                        .padding(.vertical, 4)
                        .sharpitSurface(.panel)
                        .sharpitCardSpecularBorder()
                    }
                }

                // Helper footer
                Text("Ensuite : Remplir ma semaine pour poser les séances, Ajuster le planning pour réarranger la charge.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.75))
                    .padding(.horizontal, 4)
                    .padding(.top, SharpitSpacing.xs)

                // Archive Button
                Button(role: .destructive) {
                    showingArchiveAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isArchiving ? "Archivage en cours…" : "Archiver ce plan macro")
                            .font(SharpitTypography.bodyEmphasis)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(SharpitColor.destructive)
                    .background(SharpitColor.destructive.opacity(0.1), in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
                }
                .disabled(isArchiving)
                .padding(.top, SharpitSpacing.sm)
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
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SharpitColor.primary)
                        Text("Définir un plan macro")
                            .font(SharpitTypography.cardTitle)
                            .foregroundStyle(SharpitColor.foreground)
                    }

                    Text("Une course datée sert de jalon. Le plan macro calcule les blocs de charge et les phases jusqu'à l'objectif, sans poser les séances quotidiennes.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineSpacing(3)
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
                .sharpitCardSpecularBorder()

                if datedGoals.isEmpty {
                    VStack(spacing: SharpitSpacing.sm) {
                        Image(systemName: "target")
                            .font(.system(size: 28))
                            .foregroundStyle(SharpitColor.mutedForeground)
                        Text("Aucun objectif avec date cible à venir")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Text("Ajoute un objectif ou une course dans ton profil pour générer un plan macro adapté.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(SharpitSpacing.xl)
                    .sharpitSurface(.panel)
                    .sharpitCardSpecularBorder()
                } else {
                    VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                        Text("OBJECTIF CIBLÉ")
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.mutedForeground)

                        Picker("Objectif", selection: $selectedGoalId) {
                            ForEach(datedGoals) { goal in
                                Text(formatGoalLabel(goal)).tag(goal.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(SharpitColor.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SharpitColor.secondary.opacity(0.45), in: RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.destructive)
                        }

                        Button {
                            Task { await generateNewPlan() }
                        } label: {
                            HStack(spacing: 8) {
                                if isGenerating {
                                    ProgressView()
                                        .tint(SharpitColor.primaryForeground)
                                    Text("Génération en cours…")
                                } else {
                                    Image(systemName: "wand.and.stars")
                                    Text("Générer le plan macro")
                                }
                            }
                            .font(SharpitTypography.bodyEmphasis)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(SharpitColor.primaryForeground)
                            .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
                        }
                        .disabled(isGenerating || selectedGoalId.isEmpty)
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .sharpitSurface(.panel)
                    .sharpitCardSpecularBorder()
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
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
            SharpitHaptics.play(.success)
        } catch {
            errorMessage = error.localizedDescription
            SharpitHaptics.play(.soft)
        }
        isGenerating = false
    }

    private func archiveCurrentPlan() async {
        guard let currentPlan = plan else { return }
        isArchiving = true
        do {
            let token = try await tokenProvider()
            try await trainingPlanClient.archivePlan(id: currentPlan.id, token: token)
            plan = nil
            onPlanChanged()
            SharpitHaptics.play(.success)
        } catch {
            errorMessage = error.localizedDescription
            SharpitHaptics.play(.soft)
        }
        isArchiving = false
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

    private func formatGoalLabel(_ goal: V1Goal) -> String {
        guard let date = goal.targetDate else { return goal.title }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return "\(goal.title) · \(f.string(from: date))"
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

// MARK: - MacroPhaseRailView

private struct MacroPhaseRailView: View {
    let plan: V1TrainingPlan

    var body: some View {
        let runs = computePhaseRuns(plan.weeks)
        HStack(spacing: 3) {
            ForEach(runs, id: \.phase) { run in
                VStack(alignment: .leading, spacing: 3) {
                    Rectangle()
                        .fill(run.isCurrent ? SharpitColor.primary : SharpitColor.border.opacity(0.6))
                        .frame(height: 3)
                        .clipShape(Capsule())

                    Text(run.phase.shortLabel)
                        .font(.system(size: 10, weight: run.isCurrent ? .bold : .medium, design: .rounded))
                        .foregroundStyle(run.isCurrent ? SharpitColor.foreground : SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func computePhaseRuns(_ weeks: [V1PlanWeek]) -> [(phase: V1PlanPhase, isCurrent: Bool)] {
        var runs: [V1PlanPhase] = []
        for week in weeks {
            if runs.last != week.phase {
                runs.append(week.phase)
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

        return runs.map { phase in
            (phase: phase, isCurrent: phase == currentPhase)
        }
    }
}

// MARK: - MacroWeekRowView

private struct MacroWeekRowView: View {
    let week: V1PlanWeek

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(weekDateString(week.weekStart))
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)

                    if isCurrentWeek(week.weekStart) {
                        Text("CETTE SEMAINE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SharpitColor.primary.opacity(0.12), in: Capsule())
                    }
                }

                if week.isDeload {
                    Text("Récupération")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRecovery)
                } else if let focus = week.focus, !focus.isEmpty {
                    Text(focus)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }

            Spacer(minLength: SharpitSpacing.xs)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(week.targetLoad))")
                    .font(SharpitTypography.instrument)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)

                Text("TSS")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .padding(.vertical, 10)
    }

    private func weekDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
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
