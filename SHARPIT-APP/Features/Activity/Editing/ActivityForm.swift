import SwiftUI

/// « Saisir une séance » and « Modifier la séance »: one sheet, the same fields.
///
/// A new session waits for the server: the figures the detail shows (pace, load, the plan it
/// counts for) are the server's, so the confirm button turns into a spinner, and a refusal is
/// said under the form, the form left as typed. An edit never makes the athlete wait: the sheet
/// closes on the tap, the write goes out behind, and a refusal lands in the app's toast.
/// A half-typed session is not thrown away by a swipe: « Annuler » says it.
struct ActivityFormSheet: View {
    enum Mode {
        case create
        case edit(id: String)
    }

    let mode: Mode
    let client: any ActivityMutating
    let tokenProvider: () async throws -> String
    /// Called once the server has it, with the activity's id.
    let onSaved: (String) -> Void
    /// Called on the tap of an edit, with the draft as typed, so the page shows it before the server answers.
    let onEdited: (ActivityDraft) -> Void

    @State private var draft: ActivityDraft
    private let original: ActivityDraft
    @State private var isSaving = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(
        mode: Mode,
        draft: ActivityDraft,
        client: any ActivityMutating,
        tokenProvider: @escaping () async throws -> String,
        onEdited: @escaping (ActivityDraft) -> Void = { _ in },
        onSaved: @escaping (String) -> Void
    ) {
        self.mode = mode
        self.client = client
        self.tokenProvider = tokenProvider
        self.onEdited = onEdited
        self.onSaved = onSaved
        original = draft
        _draft = State(initialValue: draft)
    }

    private var isCreating: Bool {
        if case .create = mode { true } else { false }
    }

    private var canSave: Bool {
        draft.missingRequirement == nil && (isCreating || draft != original)
    }

    var body: some View {
        NavigationStack {
            ActivityFormContent(draft: $draft, requirement: draft.missingRequirement, failure: failure)
                .navigationTitle(isCreating ? String(localized: "Saisir une séance") : String(localized: "Modifier la séance"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button(isCreating ? String(localized: "Ajouter") : String(localized: "Enregistrer")) { Task { await save() } }
                                .disabled(!canSave)
                        }
                    }
                }
        }
        .interactiveDismissDisabled(draft != original || isSaving)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func save() async {
        if case .edit(let existing) = mode {
            saveInBackground(existing)
            return
        }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            let fields = draft.creation()
            let id = try await SharpitRetry.run {
                try await client.createActivity(fields, token: try await tokenProvider())
            }
            onSaved(id)
            dismiss()
        } catch let SharpitAPIError.message(reason) {
            failure = reason
        } catch let error as SharpitAPIError where [.transport, .rateLimited, .unauthorized].contains(error) {
            failure = SharpitErrorGuidance.message(for: error, subject: String(localized: "La séance"))
        } catch {
            failure = String(localized: "La séance n’a pas pu être ajoutée. Réessaie dans un instant.")
        }
    }

    /// The edit shows on the tap: the sheet closes, the write goes out behind, and a refusal
    /// reaches the app's toast because the sheet is gone by then.
    private func saveInBackground(_ id: String) {
        let fields = draft.changes(from: original)
        let client = client
        let tokenProvider = tokenProvider
        let onSaved = onSaved
        onEdited(draft)
        dismiss()
        Task {
            do {
                try await SharpitRetry.run {
                    try await client.updateActivity(id: id, fields: fields, token: try await tokenProvider())
                }
                onSaved(id)
            } catch {
                SharpitWriteFailures.shared.report(String(localized: "Modification non enregistrée."))
            }
        }
    }
}

/// The fields of a done session, in the order the athlete remembers it: what, when, how long,
/// what the watch would have said, then how it felt.
private struct ActivityFormContent: View {
    @Binding var draft: ActivityDraft
    let requirement: String?
    let failure: String?

    private let grid = Array(repeating: GridItem(.flexible(), spacing: SharpitSpacing.xs), count: 3)
    private let rpeGrid = Array(repeating: GridItem(.flexible(), spacing: SharpitSpacing.xxs), count: 5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                sportPicker
                SharpitFormField(String(localized: "Titre (facultatif)"), placeholder: draft.sport.label, text: $draft.title)
                whenField
                durationField
                if draft.isStrength {
                    StrengthExercisesEditor(exercises: $draft.exercises)
                } else if draft.measuresDistance || draft.measuresElevation {
                    measures
                }
                rpePicker
                feelingPicker
                notesField
                messages
            }
            .padding(SharpitSpacing.pageInset)
            .animation(SharpitMotion.reveal, value: draft.sport)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SharpitCanvasBackground())
    }

    private var sportPicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(String(localized: "Sport"))
            Picker("Sport", selection: $draft.sport) {
                ForEach(ActivityDraft.sports, id: \.self) { sport in
                    Label { Text(sport.label) } icon: { Image(sharpitSymbol: sport.symbolName) }.tag(sport)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitFieldWell()
        }
    }

    private var whenField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(String(localized: "Quand"))
            DatePicker("Début", selection: $draft.date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                .font(SharpitTypography.body)
                .sharpitFieldWell()
        }
        .tint(SharpitColor.primary)
        .environment(\.locale, AppLanguage.locale)
    }

    private var durationField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(String(localized: "Durée"))
            Stepper(value: duration, in: 5...1440, step: 5) {
                Text(draft.durationMin.map(PlannedSessionFormat.duration) ?? String(localized: "Non précisée"))
                    .font(SharpitTypography.body)
                    .monospacedDigit()
                    .foregroundStyle(draft.durationMin == nil ? SharpitColor.mutedForeground : SharpitColor.foreground)
                    .contentTransition(.numericText())
            }
            .sharpitFieldWell()
        }
    }

    private var measures: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            if draft.measuresDistance {
                SharpitFormField(
                    String(localized: "Distance (\(draft.distanceUnit))"),
                    placeholder: draft.sport == .swim ? "1500" : "10,0",
                    text: $draft.distanceText,
                    keyboard: .decimalPad
                )
            }
            if let pace = draft.paceText {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    SharpitFieldLabel(String(localized: "Allure"))
                    Text(pace)
                        .font(SharpitTypography.body)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .sharpitFieldWell()
                }
            }
            if draft.measuresElevation {
                SharpitFormField(String(localized: "Dénivelé positif (m)"), placeholder: "120", text: $draft.elevationText, keyboard: .numberPad)
            }
            if draft.measuresHeartRate {
                SharpitFormField(String(localized: "FC moyenne (bpm)"), placeholder: "145", text: $draft.avgHrText, keyboard: .numberPad)
            }
        }
        .transition(.opacity)
    }

    private var rpePicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(String(localized: "Effort perçu (RPE)"))
            LazyVGrid(columns: rpeGrid, spacing: SharpitSpacing.xxs) {
                ForEach(1...10, id: \.self) { value in
                    OnboardingChoiceChip(title: "\(value)", isSelected: draft.rpe == value) {
                        // A second tap on the pick takes it back: the effort is optional.
                        SharpitMotion.run(SharpitMotion.selection) { draft.rpe = draft.rpe == value ? nil : value }
                    }
                    .accessibilityLabel("Effort \(value) sur 10")
                }
            }
        }
    }

    private var feelingPicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(String(localized: "Ressenti"))
            LazyVGrid(columns: grid, spacing: SharpitSpacing.xs) {
                ForEach(SessionFeeling.allCases) { feeling in
                    OnboardingChoiceChip(title: feeling.storedValue, isSelected: draft.feeling == feeling) {
                        SharpitMotion.run(SharpitMotion.selection) {
                            draft.feeling = draft.feeling == feeling ? nil : feeling
                        }
                    }
                }
            }
            if let feeling = draft.feeling {
                Text(feeling.hint)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(String(localized: "Notes"))
            TextField("Ce qu’il faut retenir de la séance", text: $draft.notes, axis: .vertical)
                .font(SharpitTypography.body)
                .lineLimit(3...8)
                .padding(.vertical, SharpitSpacing.sm)
                .sharpitFieldWell()
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.signalRisk)
                .fixedSize(horizontal: false, vertical: true)
        } else if let requirement {
            Text(requirement)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }

    private var duration: Binding<Int> {
        Binding(get: { draft.durationMin ?? 45 }, set: { draft.durationMin = $0 })
    }
}

/// What the edit sheet opens on: the activity as the page shows it.
struct ActivityEditing: Identifiable {
    let id: String
    let draft: ActivityDraft
    let mutator: any ActivityMutating
}

/// A done session's « … », in the page's floating controls: Modifier, the goal, then Supprimer
/// apart, as the system's menus put a destructive action.
struct ActivityActionsMenu: View {
    /// Whether the session is raced for a goal: « Lier à un objectif », or change and « Délier ».
    var isLinkedToGoal = false
    let onEdit: () -> Void
    var onPickGoal: () -> Void = {}
    var onUnlinkGoal: () -> Void = {}
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button("Modifier", systemImage: "pencil", action: onEdit)
            if isLinkedToGoal {
                Button("Changer d’objectif", systemImage: "flag", action: onPickGoal)
                Button("Délier l’objectif", systemImage: "flag.slash", action: onUnlinkGoal)
            } else {
                Button("Lier à un objectif", systemImage: "flag", action: onPickGoal)
            }
            Divider()
            SharpitDeleteMenuButton(action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .sharpitShadow(.control)
        }
        .accessibilityLabel("Actions sur la séance")
    }
}
