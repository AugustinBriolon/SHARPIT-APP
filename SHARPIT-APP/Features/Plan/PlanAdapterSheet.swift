import SwiftUI

struct PlanAdapterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    let tokenProvider: () async throws -> String
    var onPlanChanged: () -> Void = {}

    @State private var focusText: String = ""

    enum Phase {
        case idle
        case analyzing(reasoning: String)
        case results(result: V1AdaptPlanResult, selected: Set<Int>)
        case applying
    }

    @State private var phase: Phase = .idle
    @State private var errorMessage: String?

    private let coachPlanClient = CoachPlanClient()
    private let plannedSessionClient = PlannedSessionClient()

    var body: some View {
        NavigationStack {
            ZStack {
                SharpitCanvasBackground()

                switch phase {
                case .idle:
                    configForm
                case .analyzing(let reasoning):
                    analyzingView(reasoning: reasoning)
                case .results(let result, let selected):
                    resultsView(result: result, selected: selected)
                case .applying:
                    applyingView
                }
            }
            .navigationTitle("Ajuster le planning")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.primary)
                }
            }
        }
    }

    // MARK: - Initial Form

    private var configForm: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                // Intro Panel
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SharpitColor.primary)
                        Text("Ajustement dynamique")
                            .font(SharpitTypography.cardTitle)
                            .foregroundStyle(SharpitColor.foreground)
                    }

                    Text("Le coach analyse ce que tu as réellement fait et propose des modifications ciblées sur tes séances déjà planifiées (14 prochains jours), sans tout effacer.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineSpacing(3)
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
                .sharpitCardSpecularBorder()

                // Request Panel
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONTEXTE OU CONTRAINTES PARTICULIÈRES (OPTIONNEL)")
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.mutedForeground)

                        TextField(
                            "Ex : douleur au mollet, semaine de déplacement, fatigue accumulée…",
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

                    Button {
                        Task { await runAdaptation() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.rays")
                            Text("Analyser & Proposer des ajustements")
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

    private func analyzingView(reasoning: String) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(SharpitColor.primary)
                    Text("Analyse de la charge et du calendrier…")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                }
                .padding(SharpitSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sharpitSurface(.panel)
                .sharpitCardSpecularBorder()

                if !reasoning.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ANALYSE DU COACH EN DIRECT")
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

    private func resultsView(result: V1AdaptPlanResult, selected: Set<Int>) -> some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    // Summary Banner
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Synthèse des ajustements")
                            .font(SharpitTypography.cardTitle)
                            .foregroundStyle(SharpitColor.foreground)

                        if !result.summary.isEmpty {
                            Text(result.summary)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                                .lineSpacing(3)
                        }
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .sharpitSurface(.panel)
                    .sharpitCardSpecularBorder()

                    if result.changes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(SharpitColor.signalRecovery)
                            Text("Aucun ajustement nécessaire")
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.foreground)
                            Text("Ton planning actuel est parfaitement calibré avec tes capacités et ta récupération.")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(SharpitSpacing.xl)
                        .sharpitSurface(.panel)
                        .sharpitCardSpecularBorder()
                    } else {
                        // Changes List
                        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                            Text("PROPOSITIONS DU COACH")
                                .font(SharpitTypography.label)
                                .tracking(SharpitTypography.labelTracking)
                                .foregroundStyle(SharpitColor.mutedForeground)
                                .padding(.horizontal, 4)

                            ForEach(Array(result.changes.enumerated()), id: \.offset) { index, change in
                                let isChecked = selected.contains(index)
                                Button {
                                    toggleChange(index)
                                } label: {
                                    AdaptChangeRow(change: change, isChecked: isChecked)
                                }
                                .buttonStyle(.sharpitPressable)
                            }
                        }
                    }
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.vertical, SharpitSpacing.md)
            }

            // Bottom Actions Bar
            if !result.changes.isEmpty {
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
                            Task { await applySelectedChanges(result: result, selected: selected) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                Text("Appliquer \(selected.count) modification\(selected.count > 1 ? "s" : "")")
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
    }

    private var applyingView: some View {
        VStack(spacing: SharpitSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(SharpitColor.primary)
            Text("Application des modifications au planning…")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func runAdaptation() async {
        phase = .analyzing(reasoning: "")
        errorMessage = nil
        do {
            let token = try await tokenProvider()
            let result = try await coachPlanClient.adaptPlan(
                days: 14,
                focus: focusText,
                token: token,
                onReasoning: { liveReasoning in
                    Task { @MainActor in
                        phase = .analyzing(reasoning: liveReasoning)
                    }
                }
            )
            let allIndices = Set(0..<result.changes.count)
            phase = .results(result: result, selected: allIndices)
            SharpitHaptics.play(.success)
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
            SharpitHaptics.play(.soft)
        }
    }

    private func toggleChange(_ index: Int) {
        guard case .results(let result, var selected) = phase else { return }
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
        phase = .results(result: result, selected: selected)
        SharpitHaptics.play(.light)
    }

    private func applySelectedChanges(result: V1AdaptPlanResult, selected: Set<Int>) async {
        phase = .applying
        do {
            let token = try await tokenProvider()
            for index in selected.sorted() {
                guard index < result.changes.count else { continue }
                let change = result.changes[index]
                switch change.action {
                case .add:
                    let payload = CreatePlannedSessionPayload(
                        type: change.type?.rawValue ?? "OTHER",
                        date: "\(change.date ?? "2026-09-24")T12:00:00Z",
                        title: change.title,
                        description: change.description,
                        durationMin: change.durationMin,
                        load: change.load,
                        intensity: change.intensity,
                        decisionId: change.decisionId
                    )
                    _ = try await plannedSessionClient.createSession(payload, token: token)

                case .modify:
                    if let sessionId = change.sessionId {
                        let patch = UpdatePlannedSessionPayload(
                            type: change.type?.rawValue,
                            date: change.date.map { "\($0)T12:00:00Z" },
                            title: change.title,
                            description: change.description,
                            durationMin: change.durationMin,
                            load: change.load,
                            intensity: change.intensity
                        )
                        _ = try await plannedSessionClient.updateSession(id: sessionId, patch: patch, token: token)
                    }

                case .remove:
                    if let sessionId = change.sessionId {
                        try await plannedSessionClient.deleteSession(id: sessionId, token: token)
                    }
                }
            }

            toastCenter?.show(
                "\(selected.count) modification\(selected.count > 1 ? "s" : "") appliquée\(selected.count > 1 ? "s" : "")",
                symbol: "slider.horizontal.3",
                tone: .success,
                autoDismissAfter: 3.0
            )
            onPlanChanged()
            SharpitHaptics.play(.success)
            dismiss()
        } catch {
            errorMessage = "Erreur lors de l'application : \(error.localizedDescription)"
            phase = .results(result: result, selected: selected)
            SharpitHaptics.play(.soft)
        }
    }
}

// MARK: - AdaptChangeRow

private struct AdaptChangeRow: View {
    let change: V1AdaptChange
    let isChecked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isChecked ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.5))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    actionBadge(change.action)

                    if let type = change.type {
                        Text(type.label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }

                    if let dateStr = change.date {
                        Text(formatDayLabel(dateStr))
                            .font(SharpitTypography.label)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }

                    Spacer()

                    if let duration = change.durationMin, duration > 0 {
                        Text("\(Int(duration)) min")
                            .font(SharpitTypography.instrument)
                            .monospacedDigit()
                            .foregroundStyle(SharpitColor.foreground)
                    }
                }

                if let title = change.title, !title.isEmpty {
                    Text(title)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                }

                if !change.reason.isEmpty {
                    Text(change.reason)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineSpacing(2)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
        .opacity(isChecked ? 1.0 : 0.6)
    }

    @ViewBuilder
    private func actionBadge(_ action: V1AdaptAction) -> some View {
        let (color, text) = switch action {
        case .add: (SharpitColor.signalRecovery, "AJOUTER")
        case .modify: (SharpitColor.highlight, "MODIFIER")
        case .remove: (SharpitColor.destructive, "SUPPRIMER")
        }

        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(SharpitTypography.labelTracking)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.12), in: Capsule())
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
