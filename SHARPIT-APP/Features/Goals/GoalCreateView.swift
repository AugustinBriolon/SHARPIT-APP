import SwiftUI

/// A new goal, pushed in the Objectifs stack rather than presented over it: Objectifs is
/// already a sheet, and a sheet over a sheet is a stack the athlete cannot see.
struct GoalCreateView: View {
    @Bindable var store: GoalStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = GoalDraft.new()
    @State private var isSubmitting = false

    var body: some View {
        GoalFormFields(draft: $draft)
            .navigationTitle("Nouvel objectif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        Task { await submit() }
                    }
                    .disabled(draft.missingRequirement != nil || isSubmitting)
                }
            }
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
                        store.update(goal, with: draft, from: original)
                        dismiss()
                    }
                    .disabled(draft.missingRequirement != nil || draft == original)
                }
            }
    }
}

/// The goal's fields, shared by the creation and the edit so the two never drift.
private struct GoalFormFields: View {
    @Binding var draft: GoalDraft
    var footer: String?

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
                    Picker("Priorité", selection: $draft.priority) {
                        ForEach(GoalPriority.allCases) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
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
}
