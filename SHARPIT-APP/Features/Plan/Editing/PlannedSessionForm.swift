import SwiftUI

/// « Nouvelle séance »: a sheet of its own, opened from Plan's « + ».
///
/// The one write in Plan that waits for the server — the session needs its id — so « Ajouter »
/// turns into a spinner while it goes, and a refusal is said under the form in the server's
/// words, the form left as typed.
struct PlannedSessionCreateSheet: View {
    let editor: PlanEditor

    @State private var draft: PlannedSessionDraft
    private let initial: PlannedSessionDraft
    @State private var isSaving = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(editor: PlanEditor, day: Date) {
        self.editor = editor
        let start = PlannedSessionDraft.new(on: day)
        initial = start
        _draft = State(initialValue: start)
    }

    private var requirement: String? { draft.missingRequirement() }

    var body: some View {
        NavigationStack {
            PlannedSessionFormContent(draft: $draft, original: nil, requirement: requirement, failure: failure)
                .navigationTitle("Nouvelle séance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Ajouter") { Task { await create() } }
                                .disabled(requirement != nil)
                        }
                    }
                }
        }
        // A half-typed session is not thrown away by a swipe: « Annuler » says it.
        .interactiveDismissDisabled(draft != initial || isSaving)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func create() async {
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            try await editor.create(draft)
            dismiss()
        } catch let SharpitAPIError.message(reason) {
            failure = reason
        } catch let error as SharpitAPIError where [.transport, .rateLimited, .unauthorized].contains(error) {
            failure = SharpitErrorGuidance.message(for: error, subject: "La séance")
        } catch {
            failure = "La séance n’a pas pu être ajoutée. Réessaie dans un instant."
        }
    }
}

/// « Modifier la séance »: pushed inside the session's drawer — one sheet at a time — and
/// back to the drawer on « Enregistrer », which already shows the change.
struct PlannedSessionEditPage: View {
    let session: V1PlannedSessionItem
    let editor: PlanEditor
    let onSaved: (V1PlannedSessionItem) -> Void

    @State private var draft: PlannedSessionDraft
    private let original: PlannedSessionDraft
    @Environment(\.dismiss) private var dismiss

    init(session: V1PlannedSessionItem, editor: PlanEditor, onSaved: @escaping (V1PlannedSessionItem) -> Void) {
        self.session = session
        self.editor = editor
        self.onSaved = onSaved
        let draft = PlannedSessionDraft(session: session)
        original = draft
        _draft = State(initialValue: draft)
    }

    private var requirement: String? { draft.missingRequirement(editing: original) }

    var body: some View {
        PlannedSessionFormContent(draft: $draft, original: original, requirement: requirement, failure: nil)
            .navigationTitle("Modifier la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSaved(editor.save(draft, from: original, of: session))
                        dismiss()
                    }
                    .disabled(draft == original || requirement != nil)
                }
            }
    }
}

/// The fields of a planned session, in the order the athlete thinks of them: what, when, how
/// long and how hard, then what to do.
struct PlannedSessionFormContent: View {
    @Binding var draft: PlannedSessionDraft
    /// The session as it was before this edit; nil for a new one.
    let original: PlannedSessionDraft?
    let requirement: String?
    let failure: String?

    private let grid = Array(repeating: GridItem(.flexible(), spacing: SharpitSpacing.xs), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                sportPicker
                SharpitFormField("Titre (facultatif)", placeholder: draft.sport.label, text: $draft.title)
                whenFields
                durationField
                intensityPicker
                if draft.isStrength {
                    StrengthExercisesEditor(exercises: $draft.exercises)
                } else {
                    descriptionField
                }
                messages
            }
            .padding(SharpitSpacing.pageInset)
            .animation(SharpitMotion.reveal, value: draft.isStrength)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SharpitCanvasBackground())
    }

    private var sportPicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Sport")
            LazyVGrid(columns: grid, spacing: SharpitSpacing.xs) {
                ForEach(PlannedSessionDraft.sports, id: \.self) { sport in
                    OnboardingChoiceChip(title: sport.label, symbol: sport.symbolName, isSelected: draft.sport == sport) {
                        SharpitMotion.run(SharpitMotion.selection) { draft.sport = sport }
                    }
                }
            }
        }
    }

    private var whenFields: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Quand")
            DatePicker("Jour", selection: $draft.day, displayedComponents: .date)
                .font(SharpitTypography.body)
                .sharpitFieldWell()
            Toggle("Heure précise", isOn: hasStartTime)
                .font(SharpitTypography.body)
                .tint(SharpitColor.primary)
                .sharpitFieldWell()
            if draft.startTime != nil {
                DatePicker("Heure", selection: startTime, displayedComponents: .hourAndMinute)
                    .font(SharpitTypography.body)
                    .sharpitFieldWell()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tint(SharpitColor.primary)
        .environment(\.locale, Locale(identifier: "fr_FR"))
        .animation(SharpitMotion.reveal, value: draft.startTime != nil)
    }

    private var durationField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Durée")
            Stepper(value: duration, in: 5...600, step: 5) {
                Text(draft.durationMin.map(PlannedSessionFormat.duration) ?? "Non précisée")
                    .font(SharpitTypography.body)
                    .monospacedDigit()
                    .foregroundStyle(draft.durationMin == nil ? SharpitColor.mutedForeground : SharpitColor.foreground)
                    .contentTransition(.numericText())
            }
            .sharpitFieldWell()
        }
    }

    private var intensityPicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Intensité")
            LazyVGrid(columns: grid, spacing: SharpitSpacing.xs) {
                ForEach(PlannedSessionIntensity.allCases) { intensity in
                    OnboardingChoiceChip(title: intensity.label, isSelected: draft.intensity == intensity) {
                        // A second tap on the pick takes it back: intensity is optional.
                        SharpitMotion.run(SharpitMotion.selection) {
                            draft.intensity = draft.intensity == intensity ? nil : intensity
                        }
                    }
                }
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Déroulé")
            TextField(
                "Ex. : 15 min d’échauffement, 5 × 3 min au seuil, 10 min de retour au calme",
                text: $draft.description,
                axis: .vertical
            )
            .font(SharpitTypography.body)
            .lineLimit(4...10)
            .padding(.vertical, SharpitSpacing.sm)
            .sharpitFieldWell()
            if let stepsNote {
                Text(stepsNote)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What happens to the coach's structured steps, which this form does not edit.
    private var stepsNote: String? {
        guard let original, original.hasStructuredSteps else { return nil }
        return draft.sport == original.sport
            ? "Les étapes détaillées du coach restent telles quelles."
            : "Changer de sport retire les étapes détaillées du coach."
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

    // MARK: - Bindings

    private var hasStartTime: Binding<Bool> {
        Binding(
            get: { draft.startTime != nil },
            set: { on in
                draft.startTime = on
                    ? Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: draft.day)
                    : nil
            }
        )
    }

    private var startTime: Binding<Date> {
        Binding(get: { draft.startTime ?? draft.day }, set: { draft.startTime = $0 })
    }

    private var duration: Binding<Int> {
        Binding(
            get: { draft.durationMin ?? PlannedSessionDraft.defaultDurationMin },
            set: { draft.durationMin = $0 }
        )
    }
}

/// A strength session's exercises: each one named, its sets, reps and load.
struct StrengthExercisesEditor: View {
    @Binding var exercises: [StrengthExerciseDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Exercices")
            ForEach($exercises) { $exercise in
                exerciseCard($exercise)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Button {
                SharpitMotion.run(SharpitMotion.reveal) { exercises.append(StrengthExerciseDraft()) }
            } label: {
                Label("Ajouter un exercice", systemImage: "plus.circle.fill")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
                    .frame(maxWidth: .infinity, minHeight: SharpitSpacing.minimumTouchTarget, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            // An empty list opens on one row to fill rather than on a button to find.
            if exercises.isEmpty { exercises.append(StrengthExerciseDraft()) }
        }
    }

    private func exerciseCard(_ exercise: Binding<StrengthExerciseDraft>) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                TextField("Exercice (ex. : squat)", text: exercise.name)
                    .font(SharpitTypography.bodyEmphasis)
                    .textInputAutocapitalization(.sentences)
                Button(role: .destructive) {
                    let id = exercise.wrappedValue.id
                    SharpitMotion.run(SharpitMotion.reveal) { exercises.removeAll { $0.id == id } }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(SharpitColor.signalRisk)
                        .frame(width: SharpitSpacing.minimumTouchTarget, height: SharpitSpacing.minimumTouchTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retirer \(exercise.wrappedValue.name.isEmpty ? "l’exercice" : exercise.wrappedValue.name)")
            }
            Divider()
            Stepper(value: exercise.sets, in: StrengthExerciseDraft.setsRange) {
                Text("\(exercise.wrappedValue.sets) \(exercise.wrappedValue.sets > 1 ? "séries" : "série")")
                    .monospacedDigit()
            }
            Stepper(value: exercise.reps, in: StrengthExerciseDraft.repsRange) {
                Text("\(exercise.wrappedValue.reps) répétitions")
                    .monospacedDigit()
            }
            HStack {
                Text("Charge")
                Spacer()
                TextField("Poids du corps", value: exercise.weightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                Text("kg")
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .font(SharpitTypography.body)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

/// How the plan's forms word a figure.
enum PlannedSessionFormat {
    /// « 45 min », « 1 h 30 », « 2 h ».
    static func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : String(format: "%d h %02d", hours, rest)
    }
}
