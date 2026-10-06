import SwiftUI

/// « Saisir une séance » and « Modifier la séance »: one sheet, the same fields.
///
/// Both wait for the server — the figures the detail shows (pace, load, the plan it counts for)
/// are the server's, computed from what is sent — so the confirm button turns into a spinner
/// while it goes, and a refusal is said under the form in the server's words, the form left as
/// typed. A half-typed session is not thrown away by a swipe: « Annuler » says it.
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
        onSaved: @escaping (String) -> Void
    ) {
        self.mode = mode
        self.client = client
        self.tokenProvider = tokenProvider
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
                .navigationTitle(isCreating ? "Saisir une séance" : "Modifier la séance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button(isCreating ? "Ajouter" : "Enregistrer") { Task { await save() } }
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
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            let id: String
            switch mode {
            case .create:
                let fields = draft.creation()
                id = try await SharpitRetry.run {
                    try await client.createActivity(fields, token: try await tokenProvider())
                }
            case .edit(let existing):
                let fields = draft.changes(from: original)
                try await SharpitRetry.run {
                    try await client.updateActivity(id: existing, fields: fields, token: try await tokenProvider())
                }
                id = existing
            }
            onSaved(id)
            dismiss()
        } catch let SharpitAPIError.message(reason) {
            failure = reason
        } catch let error as SharpitAPIError where [.transport, .rateLimited, .unauthorized].contains(error) {
            failure = SharpitErrorGuidance.message(for: error, subject: "La séance")
        } catch {
            failure = isCreating
                ? "La séance n’a pas pu être ajoutée. Réessaie dans un instant."
                : "La séance n’a pas pu être modifiée. Réessaie dans un instant."
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
                SharpitFormField("Titre (facultatif)", placeholder: draft.sport.label, text: $draft.title)
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
            SharpitFieldLabel("Sport")
            LazyVGrid(columns: grid, spacing: SharpitSpacing.xs) {
                ForEach(ActivityDraft.sports, id: \.self) { sport in
                    OnboardingChoiceChip(title: sport.label, symbol: sport.symbolName, isSelected: draft.sport == sport) {
                        SharpitMotion.run(SharpitMotion.selection) { draft.sport = sport }
                    }
                }
            }
        }
    }

    private var whenField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Quand")
            DatePicker("Début", selection: $draft.date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                .font(SharpitTypography.body)
                .sharpitFieldWell()
        }
        .tint(SharpitColor.primary)
        .environment(\.locale, Locale(identifier: "fr_FR"))
    }

    private var durationField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Durée")
            Stepper(value: duration, in: 5...1440, step: 5) {
                Text(draft.durationMin.map(PlannedSessionFormat.duration) ?? "Non précisée")
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
                    "Distance (\(draft.distanceUnit))",
                    placeholder: draft.sport == .swim ? "1500" : "10,0",
                    text: $draft.distanceText,
                    keyboard: .decimalPad
                )
            }
            if draft.measuresElevation {
                SharpitFormField("Dénivelé positif (m)", placeholder: "120", text: $draft.elevationText, keyboard: .numberPad)
            }
            if draft.measuresHeartRate {
                SharpitFormField("FC moyenne (bpm)", placeholder: "145", text: $draft.avgHrText, keyboard: .numberPad)
            }
        }
        .transition(.opacity)
    }

    private var rpePicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Effort perçu (RPE)")
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
            SharpitFieldLabel("Ressenti")
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
            SharpitFieldLabel("Notes")
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

/// What a done session's « … » offers about séjours: nothing (not a hike, or not read yet), a
/// hike free to gather with others, or one already in a séjour.
enum HikeTripMenuState: Equatable {
    case hidden
    case linkable
    case member
}

/// What the edit sheet opens on: the activity as the page shows it.
struct ActivityEditing: Identifiable {
    let id: String
    let draft: ActivityDraft
    let mutator: any ActivityMutating
}

/// A done session's « … », in the page's floating controls: Modifier, the watch for a strength
/// session, then Supprimer apart, as the system's menus put a destructive action.
struct ActivityActionsMenu: View {
    let canSendToWatch: Bool
    let onEdit: () -> Void
    let onSendToWatch: () -> Void
    let onDelete: () -> Void
    /// A hike's séjour: « Voir le séjour » when it is in one, else « Lier à d'autres randonnées ».
    var hikeTrip: HikeTripMenuState = .hidden
    var onOpenHikeTrip: () -> Void = {}
    var onLinkHikes: () -> Void = {}

    var body: some View {
        Menu {
            Button("Modifier", systemImage: "pencil", action: onEdit)
            if canSendToWatch {
                Button("Envoyer à la montre", systemImage: "applewatch.radiowaves.left.and.right", action: onSendToWatch)
            }
            switch hikeTrip {
            case .hidden:
                EmptyView()
            case .linkable:
                Button("Lier à d'autres randonnées", systemImage: "link", action: onLinkHikes)
            case .member:
                Button("Voir le séjour", systemImage: "figure.hiking", action: onOpenHikeTrip)
            }
            Divider()
            Button("Supprimer", systemImage: "trash", role: .destructive, action: onDelete)
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
