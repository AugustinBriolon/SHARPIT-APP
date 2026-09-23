import SwiftUI

struct PlanGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    let tokenProvider: () async throws -> String
    var onPlanChanged: () -> Void = {}

    @State private var daysSelection: Int = 7
    @State private var selectedGoalId: String = "none"
    @State private var datedGoals: [V1Goal] = []
    @State private var focusText: String = ""

    enum Phase {
        case idle
        case generating(reasoning: String)
        case results(plan: V1GeneratedPlan, selected: Set<Int>)
        case inserting
    }

    @State private var phase: Phase = .idle
    @State private var errorMessage: String?

    private let coachPlanClient = CoachPlanClient()
    private let goalClient = GoalClient()
    private let plannedSessionClient = PlannedSessionClient()

    var body: some View {
        NavigationStack {
            ZStack {
                SharpitCanvasBackground()

                switch phase {
                case .idle:
                    configForm
                case .generating(let reasoning):
                    generatingView(reasoning: reasoning)
                case .results(let plan, let selected):
                    resultsView(plan: plan, selected: selected)
                case .inserting:
                    insertingView
                }
            }
            .navigationTitle("Remplir ma semaine")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.primary)
                }
            }
            .task { await loadGoals() }
        }
    }

    // MARK: - Configuration Form

    private var configForm: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                // Intro Panel
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SharpitColor.primary)
                        Text("Proposition sur-mesure")
                            .font(SharpitTypography.cardTitle)
                            .foregroundStyle(SharpitColor.foreground)
                    }

                    Text("Le coach propose de nouvelles séances à intégrer à ton calendrier selon ta forme et ton objectif. Tu valides chaque séance avant insertion.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineSpacing(3)
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
                .sharpitCardSpecularBorder()

                // Form Controls Panel
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    // Block Duration
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DURÉE DU BLOC")
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.mutedForeground)

                        Picker("Durée", selection: $daysSelection) {
                            Text("3 jours").tag(3)
                            Text("1 semaine").tag(7)
                            Text("2 semaines").tag(14)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Targeted Goal
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OBJECTIF CIBLÉ")
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.mutedForeground)

                        Picker("Objectif", selection: $selectedGoalId) {
                            Text("Aucun (forme générale)").tag("none")
                            ForEach(datedGoals) { goal in
                                Text(goal.title).tag(goal.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(SharpitColor.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SharpitColor.secondary.opacity(0.45), in: RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous))
                    }

                    // Specific Focus / Request
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DEMANDE SPÉCIFIQUE (OPTIONNEL)")
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.mutedForeground)

                        TextField(
                            "Ex : deux grosses sorties vélo, repos vendredi…",
                            text: $focusText,
                            axis: .vertical
                        )
                        .lineLimit(3...5)
                        .padding(10)
                        .background(SharpitColor.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                                .strokeBorder(SharpitColor.border.opacity(0.2), lineWidth: 0.5)
                        )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.destructive)
                    }

                    // Generate Button
                    Button {
                        Task { await runGeneration() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Générer les séances")
                        }
                        .font(SharpitTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
                    }
                    .padding(.top, SharpitSpacing.xs)
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
                .sharpitCardSpecularBorder()
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
    }

    // MARK: - Streaming View

    private func generatingView(reasoning: String) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(SharpitColor.primary)
                    Text("Le coach élabore ta semaine…")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                }
                .padding(SharpitSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sharpitSurface(.panel)
                .sharpitCardSpecularBorder()

                if !reasoning.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RÉFLEXION EN DIRECT")
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.mutedForeground)

                        Text(reasoning)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .sharpitSurface(.panelAlt)
                    .sharpitCardSpecularBorder()
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
    }

    // MARK: - Results View

    private func resultsView(plan: V1GeneratedPlan, selected: Set<Int>) -> some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    // Summary Banner
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(plan.sessions.count) séances proposées")
                                .font(SharpitTypography.cardTitle)
                                .foregroundStyle(SharpitColor.foreground)

                            Spacer()

                            let totalTss = plan.sessions.reduce(0.0) { $0 + $1.load }
                            Text("\(Int(totalTss)) TSS")
                                .font(SharpitTypography.data)
                                .monospacedDigit()
                                .foregroundStyle(SharpitColor.primary)
                        }

                        if !plan.summary.isEmpty {
                            Text(plan.summary)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                                .lineSpacing(3)
                        }
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .sharpitSurface(.panel)
                    .sharpitCardSpecularBorder()

                    // Sessions List
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        Text("SÉANCES À AJOUTER")
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .padding(.horizontal, 4)

                        ForEach(Array(plan.sessions.enumerated()), id: \.offset) { index, session in
                            let isChecked = selected.contains(index)
                            Button {
                                toggleSession(index)
                            } label: {
                                GeneratedSessionRow(session: session, isChecked: isChecked)
                            }
                            .buttonStyle(.sharpitPressable)
                        }
                    }
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.vertical, SharpitSpacing.md)
            }

            // Bottom Actions Bar
            VStack(spacing: 8) {
                Divider()
                    .background(SharpitColor.border.opacity(0.35))

                HStack(spacing: 12) {
                    Button("Modifier") {
                        phase = .idle
                    }
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Button {
                        Task { await insertSelectedSessions(plan: plan, selected: selected) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Insérer \(selected.count) séance\(selected.count > 1 ? "s" : "")")
                        }
                        .font(SharpitTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .background(SharpitColor.primary, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
                    }
                    .disabled(selected.isEmpty)
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.bottom, SharpitSpacing.sm)
            }
            .background(SharpitColor.background)
        }
    }

    private var insertingView: some View {
        VStack(spacing: SharpitSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(SharpitColor.primary)
            Text("Ajout des séances au planning…")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadGoals() async {
        do {
            let token = try await tokenProvider()
            let goals = try await goalClient.goals(token: token)
            let now = Date()
            datedGoals = goals.filter { !$0.achieved && ($0.targetDate ?? .distantPast) >= now }
        } catch {
            // Goals optional for general form
        }
    }

    private func runGeneration() async {
        phase = .generating(reasoning: "")
        errorMessage = nil
        do {
            let token = try await tokenProvider()
            let goalId = selectedGoalId == "none" ? nil : selectedGoalId
            let result = try await coachPlanClient.generateWeek(
                days: daysSelection,
                goalId: goalId,
                focus: focusText,
                startDate: Date(),
                token: token,
                onReasoning: { liveReasoning in
                    Task { @MainActor in
                        phase = .generating(reasoning: liveReasoning)
                    }
                }
            )
            let allIndices = Set(0..<result.sessions.count)
            phase = .results(plan: result, selected: allIndices)
            SharpitHaptics.play(.success)
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
            SharpitHaptics.play(.soft)
        }
    }

    private func toggleSession(_ index: Int) {
        guard case .results(let plan, var selected) = phase else { return }
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
        phase = .results(plan: plan, selected: selected)
        SharpitHaptics.play(.light)
    }

    private func insertSelectedSessions(plan: V1GeneratedPlan, selected: Set<Int>) async {
        phase = .inserting
        do {
            let token = try await tokenProvider()
            for index in selected.sorted() {
                guard index < plan.sessions.count else { continue }
                let s = plan.sessions[index]
                let payload = CreatePlannedSessionPayload(
                    type: s.type.rawValue,
                    date: "\(s.date)T12:00:00Z",
                    startTime: s.startTime,
                    title: s.title,
                    description: s.description,
                    durationMin: s.durationMin,
                    load: s.load,
                    intensity: s.intensity,
                    goalId: selectedGoalId == "none" ? nil : selectedGoalId,
                    decisionId: s.decisionId
                )
                _ = try await plannedSessionClient.createSession(payload, token: token)
            }
            toastCenter?.show(
                "\(selected.count) séance\(selected.count > 1 ? "s" : "") ajoutée\(selected.count > 1 ? "s" : "")",
                symbol: "calendar.badge.plus",
                tone: .success,
                autoDismissAfter: 3.0
            )
            onPlanChanged()
            SharpitHaptics.play(.success)
            dismiss()
        } catch {
            errorMessage = "Impossible d'insérer les séances : \(error.localizedDescription)"
            phase = .results(plan: plan, selected: selected)
            SharpitHaptics.play(.soft)
        }
    }
}

// MARK: - GeneratedSessionRow

private struct GeneratedSessionRow: View {
    let session: V1GeneratedSession
    let isChecked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isChecked ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.5))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: session.type.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(session.type.label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(SharpitTypography.labelTracking)
                    }
                    .foregroundStyle(SharpitSportTone.label(for: session.type.label))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(SharpitSportTone.background(for: session.type.label), in: Capsule())

                    Text(formatDayLabel(session.date))
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.mutedForeground)

                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(session.durationMin))")
                            .font(SharpitTypography.instrument)
                            .monospacedDigit()
                        Text("min")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)

                        Text("·")
                            .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))

                        Text("\(Int(session.load))")
                            .font(SharpitTypography.instrument)
                            .monospacedDigit()
                        Text("TSS")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .foregroundStyle(SharpitColor.foreground)
                }

                Text(session.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)

                if let rationale = session.rationale, !rationale.isEmpty {
                    Text(rationale)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(2)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
        .opacity(isChecked ? 1.0 : 0.6)
    }

    private func formatDayLabel(_ dateString: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dateString) else { return dateString }
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date).capitalized
    }
}
