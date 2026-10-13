import SwiftUI

/// A new goal, pushed in the Objectifs stack rather than presented over it: Objectifs is
/// already a sheet, and a sheet over a sheet is a stack the athlete cannot see.
struct GoalCreateView: View {
    @Bindable var store: GoalStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = GoalDraft.new()
    @State private var isSubmitting = false
    /// Once the athlete picks a role, the suggestion stops following the day and the format.
    @State private var roleTouched = false
    @State private var conflict: V1Goal?

    var body: some View {
        GoalFormFields(draft: $draft, onRolePicked: { roleTouched = true })
            .navigationTitle("Nouvel objectif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        conflict = draft.principalConflict(among: store.goals)
                        if conflict == nil { Task { await submit() } }
                    }
                    .disabled(draft.missingRequirement != nil || isSubmitting)
                }
            }
            .onChange(of: draft.targetDate, initial: true) { suggestRole() }
            .onChange(of: draft.raceFormat) { suggestRole() }
            .onChange(of: store.goals) { suggestRole() }
            .principalConflictConfirmation($conflict, store: store) {
                Task { await submit() }
            }
    }

    private func suggestRole() {
        guard !roleTouched else { return }
        draft.priority = GoalSeason.suggestedPriority(date: draft.targetDate, format: draft.raceFormat, among: store.goals)
    }

    /// A creation waits for the server's id: the goal's page needs it.
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        if await store.create(draft.creation) {
            dismiss()
        }
    }
}

/// An existing goal, pushed over its own page. « OK » shows the change at once and sends only
/// what moved, so a race moved to another day keeps the plan built toward it.
struct GoalEditView: View {
    let goal: V1Goal
    let store: GoalStore
    @Environment(\.dismiss) private var dismiss

    @State private var original: GoalDraft
    @State private var draft: GoalDraft
    @State private var conflict: V1Goal?

    init(goal: V1Goal, store: GoalStore) {
        self.goal = goal
        self.store = store
        let draft = GoalDraft(goal: goal)
        _original = State(initialValue: draft)
        _draft = State(initialValue: draft)
    }

    var body: some View {
        GoalFormFields(draft: $draft, footer: draft.missingRequirement)
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        conflict = movesIntoSeason ? draft.principalConflict(among: store.goals, excluding: goal.id) : nil
                        if conflict == nil { save() }
                    }
                    .disabled(draft.missingRequirement != nil || draft == original)
                }
            }
            .principalConflictConfirmation($conflict, store: store, save: save)
    }

    /// Asked only when the role or the day changed: a conflict the athlete already kept is not
    /// asked again on every edit of the notes.
    private var movesIntoSeason: Bool {
        original.priority != draft.priority || original.kind != draft.kind
            || !Calendar.current.isDate(original.targetDate, inSameDayAs: draft.targetDate)
    }

    private func save() {
        store.update(goal, with: draft, from: original)
        dismiss()
    }
}

private extension View {
    /// One principal per season: saving a principal within six months of another asks, calmly,
    /// which one the plan tapers for — nothing changes without the athlete's word.
    func principalConflictConfirmation(_ other: Binding<V1Goal?>, store: GoalStore, save: @escaping () -> Void) -> some View {
        confirmationDialog(
            "Déjà un objectif principal cette saison",
            isPresented: Binding(get: { other.wrappedValue != nil }, set: { if !$0 { other.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: other.wrappedValue
        ) { goal in
            Button("Passer \(goal.title) en course étape") {
                store.setPriority(.b, of: goal)
                save()
            }
            Button("Garder les deux") { save() }
            Button("Annuler", role: .cancel) {}
        } message: { goal in
            Text("\(goal.title) est à moins de six mois. Deux courses principales se disputent le même affûtage : le plan n’en prépare vraiment qu’une.")
        }
    }
}

/// The goal's fields, shared by the creation and the edit so the two never drift.
private struct GoalFormFields: View {
    @Binding var draft: GoalDraft
    var footer: String?
    var onRolePicked: () -> Void = {}

    var body: some View {
        Form {
            Section {
                Picker("Type d’objectif", selection: $draft.kind) {
                    ForEach(GoalKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(eyebrow: "Détails") {
                TextField("Nom de l’objectif", text: $draft.title)
                    .textInputAutocapitalization(.sentences)

                if draft.kind == .race {
                    DatePicker("Date de la course", selection: $draft.targetDate, displayedComponents: .date)
                    TextField("Format (Marathon, 70.3…)", text: $draft.raceFormat)
                    TextField("Lieu", text: $draft.location)
                        .textContentType(.addressCity)
                    TextField("Chrono visé (3h30…)", text: $draft.targetPerformance)
                } else {
                    TextField("Valeur cible", text: $draft.targetValueText)
                        .keyboardType(.decimalPad)
                    TextField("Valeur actuelle", text: $draft.currentValueText)
                        .keyboardType(.decimalPad)
                    TextField("Unité (W, km, kg…)", text: $draft.unit)
                        .textInputAutocapitalization(.never)
                    Toggle("Date cible", isOn: $draft.hasTargetDate.animation(SharpitMotion.selection))
                    if draft.hasTargetDate {
                        DatePicker("Pour le", selection: $draft.targetDate, displayedComponents: .date)
                    }
                }
            }

            if draft.kind == .race {
                Section(eyebrow: "Place dans la saison") {
                    Picker("Place dans la saison", selection: rolePick) {
                        ForEach(GoalRole.allCases) { role in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(role.label)
                                    .font(SharpitTypography.bodyEmphasis)
                                    .foregroundStyle(SharpitColor.foreground)
                                Text(role.consequence)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                            }
                            .tag(role.priority)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }

            Section {
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
            } footer: {
                if let footer {
                    SharpitListFooter(footer)
                }
            }
        }
        .sharpitGroupedList()
        .scrollDismissesKeyboard(.interactively)
    }

    private var rolePick: Binding<GoalPriority> {
        Binding(get: { draft.priority }, set: {
            draft.priority = $0
            onRolePicked()
        })
    }
}
