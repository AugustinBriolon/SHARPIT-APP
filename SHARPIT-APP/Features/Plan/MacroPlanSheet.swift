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
        let runs = MacroPlanReadout.runs(plan.weeks)
        let topLoad = plan.weeks.map(\.targetLoad).max() ?? 0
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 28) {
                MacroPlanHero(plan: plan, runs: runs, range: dateRangeString(for: plan))

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                        MacroPhaseSection(run: run, topLoad: topLoad)
                    }
                }

                if let summary = plan.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Le mot du coach")
                            .font(SharpitTypography.sectionTitle)
                            .foregroundStyle(SharpitColor.foreground)
                            .accessibilityAddTraits(.isHeader)
                        Text(summary)
                            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(SharpitColor.slate)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

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

/// The plan's head, on the sheet: where the athlete stands in it — the week, the phase and what
/// that phase is for — then the phases as a rail, each as wide as its weeks.
private struct MacroPlanHero: View {
    let plan: V1TrainingPlan
    let runs: [MacroPlanReadout.Run]
    let range: String?

    var body: some View {
        let current = runs.first(where: \.isCurrent)
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                if let range {
                    Text(range)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
                Text(MacroPlanReadout.standing(plan.weeks))
                    .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title, digits: true))
                    .tracking(-0.5)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                if let current {
                    Text("\(current.phase.label) : \(MacroPlanReadout.purpose(current.phase))")
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            MacroPhaseRailView(runs: runs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - MacroPhaseSection

/// A phase and its weeks: its mark, its name, how long it runs and what it is for — the weeks
/// under it open on a tap, the current phase's shown from the start.
private struct MacroPhaseSection: View {
    let run: MacroPlanReadout.Run
    let topLoad: Double
    @State private var isOpen: Bool

    init(run: MacroPlanReadout.Run, topLoad: Double) {
        self.run = run
        self.topLoad = topLoad
        _isOpen = State(initialValue: run.isCurrent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(SharpitMotion.fade) { isOpen.toggle() } } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MacroPlanReadout.hue(run.phase))
                        .frame(width: 4, height: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: SharpitSpacing.xs) {
                            Text(run.phase.label)
                                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                                .foregroundStyle(SharpitColor.foreground)
                            if run.isCurrent {
                                CliniqueStatusPill(String(localized: "En cours"), status: .good)
                            }
                        }
                        Text(MacroPlanReadout.span(run))
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                    }
                    Spacer(minLength: SharpitSpacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SharpitColor.slate)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityHint(isOpen ? String(localized: "Replie les semaines") : String(localized: "Montre les semaines"))

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(run.weeks) { week in
                        CliniqueDivider()
                        MacroWeekRowView(week: week, topLoad: topLoad, hue: MacroPlanReadout.hue(run.phase))
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 8)
            }
        }
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
    let runs: [MacroPlanReadout.Run]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
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
                .layoutPriority(Double(run.weeks.count))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - MacroWeekRowView

/// A week of a phase: its Monday, what it works, and its load as a bar against the plan's
/// heaviest week — this week in bold.
private struct MacroWeekRowView: View {
    let week: V1PlanWeek
    let topLoad: Double
    let hue: Color

    var body: some View {
        let isCurrent = MacroPlanReadout.isCurrent(week)
        HStack(alignment: .center, spacing: 10) {
            Text(week.weekStart.sharpitFormatted(.dateTime.day().month(.abbreviated)))
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                .foregroundStyle(SharpitColor.slate)
                .frame(width: 58, alignment: .leading)
            Text(WeekQualityLabel.from(focus: week.focus, phase: week.phase, isDeload: week.isDeload) ?? week.phase.label)
                .font(SharpitTypography.system(size: 15, weight: isCurrent ? .semibold : .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)
            Spacer(minLength: SharpitSpacing.xs)
            SharpitBarTrack(fraction: topLoad > 0 ? week.targetLoad / topLoad : 0, tone: hue)
                .frame(width: 56, height: 4)
                .accessibilityHidden(true)
            Text("\(Int(week.targetLoad))")
                .font(SharpitTypography.system(size: 14, weight: isCurrent ? .semibold : .regular, relativeTo: .footnote, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue("charge prévue \(Int(week.targetLoad))")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// The macro plan's marks and words.
enum MacroPlanReadout {
    /// A stretch of weeks in one phase.
    struct Run: Equatable {
        let phase: V1PlanPhase
        var weeks: [V1PlanWeek]
        var isCurrent: Bool
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    static func isCurrent(_ week: V1PlanWeek, now: Date = .now) -> Bool {
        calendar.isDate(week.weekStart, equalTo: now, toGranularity: .weekOfYear)
    }

    /// The weeks gathered phase by phase, in order; the one holding today is current.
    static func runs(_ weeks: [V1PlanWeek], now: Date = .now) -> [Run] {
        var runs: [Run] = []
        for week in weeks {
            if runs.last?.phase == week.phase {
                runs[runs.count - 1].weeks.append(week)
            } else {
                runs.append(Run(phase: week.phase, weeks: [week], isCurrent: false))
            }
            if isCurrent(week, now: now) { runs[runs.count - 1].isCurrent = true }
        }
        return runs
    }

    /// « Semaine 3 sur 12 » while the plan runs; its length before it starts or once it is over.
    static func standing(_ weeks: [V1PlanWeek], now: Date = .now) -> String {
        if let index = weeks.firstIndex(where: { isCurrent($0, now: now) }) {
            return String(localized: "Semaine \(index + 1) sur \(weeks.count)")
        }
        return String(localized: "\(weeks.count) semaines")
    }

    /// « 4 semaines · dès le 3 nov. »
    static func span(_ run: Run) -> String {
        let count = run.weeks.count == 1 ? String(localized: "1 semaine") : String(localized: "\(run.weeks.count) semaines")
        guard let first = run.weeks.first else { return count }
        let start = first.weekStart.sharpitFormatted(.dateTime.day().month(.abbreviated))
        return String(localized: "\(count) · dès le \(start)")
    }

    /// What a phase is for, in a few words.
    static func purpose(_ phase: V1PlanPhase) -> String {
        switch phase {
        case .base: String(localized: "du volume facile pour construire l'endurance.")
        case .build: String(localized: "l'intensité monte, semaine après semaine.")
        case .peak: String(localized: "les allures de course et les séances clés.")
        case .taper: String(localized: "la charge baisse pour arriver frais.")
        case .race: String(localized: "la semaine de ta course.")
        }
    }

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
