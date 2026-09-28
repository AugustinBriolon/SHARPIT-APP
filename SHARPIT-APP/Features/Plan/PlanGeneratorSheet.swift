import SwiftUI

/// Plan's « Remplir ma semaine »: a short request, then the week as the coach writes it, then
/// the sessions to keep. The generation lives in `PlanGenerationStore`, owned by Plan, so the
/// sheet can close and reopen on it at any point.
struct PlanGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @Bindable var store: PlanGenerationStore
    var onPlanChanged: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, SharpitSpacing.pageInset)
                    .padding(.vertical, SharpitSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .background(SharpitCanvasBackground())
            .navigationTitle("Remplir ma semaine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { await store.loadGoals() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle:
            request(error: nil)
        case .failed(let message):
            request(error: message)
        case .generating(let drafts):
            GeneratingWeekView(
                drafts: drafts,
                note: "Environ une minute. Tu peux fermer : une notification te dira quand c'est prêt."
            )
        case .ready(let plan, let selected), .inserting(let plan, let selected):
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                if !plan.summary.isEmpty {
                    Text(plan.summary)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(3)
                }
                GeneratedWeekView(
                    sessions: plan.sessions,
                    selection: selected,
                    verdicts: Dictionary(uniqueKeysWithValues: plan.sessions.indices.compactMap { index in
                        plan.verdict(at: index).map { (index, $0) }
                    }),
                    onToggle: { store.toggle($0) },
                    opening: .push
                )
                if let insertError = store.insertError {
                    Label(insertError, systemImage: "exclamationmark.triangle")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
            }
        }
    }

    private var selectedGoalTitle: String {
        store.goals.first { $0.id == store.goalId }?.title ?? "Forme générale"
    }

    private func request(error: String?) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitFieldLabel("Durée")
                Picker("Durée", selection: $store.days) {
                    Text("3 jours").tag(3)
                    Text("1 semaine").tag(7)
                    Text("2 semaines").tag(14)
                }
                .pickerStyle(.segmented)
            }

            if !store.goals.isEmpty {
                HStack(spacing: SharpitSpacing.sm) {
                    Text("Objectif")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .layoutPriority(1)
                    Spacer(minLength: SharpitSpacing.xs)
                    Menu {
                        Picker("Objectif", selection: $store.goalId) {
                            Text("Forme générale").tag(String?.none)
                            ForEach(store.goals) { goal in
                                Text(goal.title).tag(String?.some(goal.id))
                            }
                        }
                    } label: {
                        // One line whatever the goal's name: a long title is cut, never wrapped.
                        HStack(spacing: 4) {
                            Text(selectedGoalTitle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
            }

            SharpitFormField("Une demande (optionnel)", placeholder: "Deux sorties vélo, repos vendredi…", text: $store.focus)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: SharpitSpacing.xs) {
            switch store.phase {
            case .idle, .failed:
                primary(title: "Générer", busy: false) { store.start() }
            case .generating:
                // Nothing to do but wait or close — « Fermer » is in the bar.
                EmptyView()
            case .ready(_, let selected), .inserting(_, let selected):
                let busy = if case .inserting = store.phase { true } else { false }
                primary(
                    title: busy ? "Ajout au plan…" : "Ajouter \(selected.count) séance\(selected.count > 1 ? "s" : "")",
                    busy: busy
                ) {
                    Task { await insert() }
                }
                .disabled(selected.isEmpty || busy)
                Button("Recommencer") { store.reset() }
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .disabled(busy)
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.vertical, SharpitSpacing.sm)
        // The list scrolls under the actions: a fade keeps « Recommencer » readable over it.
        .background(
            LinearGradient(
                colors: [SharpitColor.background.opacity(0), SharpitColor.background.opacity(0.9), SharpitColor.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func primary(title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.xs) {
                if busy { ProgressView().tint(SharpitColor.primaryForeground) }
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primaryForeground)
            }
            .frame(maxWidth: .infinity)
        }
        .sharpitGlassButton(prominent: true)
        .tint(SharpitColor.primary)
    }

    private func insert() async {
        guard let count = await store.insert() else {
            SharpitHaptics.play(.soft)
            return
        }
        toastCenter?.show(
            "\(count) séance\(count > 1 ? "s" : "") ajoutée\(count > 1 ? "s" : "")",
            symbol: "calendar.badge.plus",
            tone: .success,
            autoDismissAfter: 3.0
        )
        SharpitHaptics.play(.success)
        onPlanChanged()
        dismiss()
    }
}
