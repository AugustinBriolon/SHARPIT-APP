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

/// The fields of a done session, in the order the athlete remembers it: what and how long on the
/// ink plate, when, what the watch would have said, then how it felt.
private struct ActivityFormContent: View {
    @Binding var draft: ActivityDraft
    let requirement: String?
    let failure: String?

    private let durationPresets = [30, 45, 60, 90, 120]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                plate
                whenCard
                if draft.isStrength {
                    StrengthExercisesEditor(exercises: $draft.exercises)
                        .padding(SharpitSpacing.cardPadding)
                        .sharpitSurface(.panel)
                } else if draft.measuresDistance || draft.measuresElevation {
                    measuresCard
                }
                effortCard
                detailsCard
                messages
            }
            .padding(SharpitSpacing.pageInset)
            .animation(SharpitMotion.reveal, value: draft.sport)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SharpitCanvasBackground())
    }

    // MARK: - Plate

    /// The sport and the time, big, with what they add up to while it is typed.
    private var plate: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            sportMenu
            durationReadout
            durationPresetRow
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
    }

    private var sportMenu: some View {
        Menu {
            Picker("Sport", selection: $draft.sport) {
                ForEach(ActivityDraft.sports, id: \.self) { sport in
                    Label { Text(sport.label) } icon: { Image(sharpitSymbol: sport.symbolName) }.tag(sport)
                }
            }
        } label: {
            HStack(spacing: SharpitSpacing.xs) {
                Image(sharpitSymbol: draft.sport.symbolName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SharpitColor.highlightForeground)
                    .frame(width: 40, height: 40)
                    .background(SharpitColor.highlight, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                Text(draft.sport.label)
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.6))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Sport")
        .accessibilityValue(draft.sport.label)
    }

    private var durationReadout: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            stepButton(symbol: "minus", label: String(localized: "Moins 5 minutes")) { draft.adjustDuration(by: -5) }
            VStack(spacing: 2) {
                Text(draft.durationMin.map(PlannedSessionFormat.duration) ?? "—")
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                summary
            }
            .frame(maxWidth: .infinity)
            stepButton(symbol: "plus", label: String(localized: "Plus 5 minutes")) { draft.adjustDuration(by: 5) }
        }
    }

    /// « 10 km · 5:30 /km »: the distance and the pace the time makes, once they can be told.
    @ViewBuilder
    private var summary: some View {
        let parts = [draft.measuresDistance && !draft.distanceText.isEmpty ? "\(draft.distanceText) \(draft.distanceUnit)" : nil, draft.paceText]
            .compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(SharpitTypography.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.inkAccent)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func stepButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            SharpitMotion.run(SharpitMotion.selection, action)
            SharpitHaptics.play(.notch(major: false))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
                .frame(width: SharpitSpacing.minimumTouchTarget, height: SharpitSpacing.minimumTouchTarget)
                .background(SharpitColor.inkSurfaceForeground.opacity(0.12), in: Circle())
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(label)
    }

    private var durationPresetRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: SharpitSpacing.xs) {
                ForEach(durationPresets, id: \.self) { minutes in
                    let isSelected = draft.durationMin == minutes
                    Button {
                        SharpitMotion.run(SharpitMotion.selection) { draft.durationMin = minutes }
                    } label: {
                        Text(PlannedSessionFormat.duration(minutes))
                            .font(SharpitTypography.bodyEmphasis)
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? SharpitColor.highlightForeground : SharpitColor.inkSurfaceForeground)
                            .padding(.horizontal, SharpitSpacing.sm)
                            .frame(minHeight: 36)
                            .background(
                                isSelected ? SharpitColor.highlight : SharpitColor.inkSurfaceForeground.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.sharpitPressable)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Cards

    private var whenCard: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitFieldLabel(String(localized: "Quand"))
            SharpitSegmentedChoice(
                options: [0, 1, 2],
                label: dayLabel,
                selection: Binding(
                    get: { dayOffset },
                    set: { if let days = $0 { draft.move(toDaysAgo: days) } }
                )
            )
            DatePicker("Début", selection: $draft.date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                .font(SharpitTypography.body)
                .sharpitFieldWell()
        }
        .tint(SharpitColor.primary)
        .environment(\.locale, AppLanguage.locale)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    /// 0, 1 or 2 when the session sits on today, yesterday or the day before; nil elsewhere.
    private var dayOffset: Int? {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: draft.date),
            to: Calendar.current.startOfDay(for: .now)
        ).day
        return days.flatMap { (0...2).contains($0) ? $0 : nil }
    }

    private func dayLabel(_ daysAgo: Int) -> String {
        switch daysAgo {
        case 0: String(localized: "Aujourd’hui")
        case 1: String(localized: "Hier")
        default: String(localized: "Avant-hier")
        }
    }

    private var measuresCard: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            if draft.measuresDistance {
                SharpitFormField(
                    String(localized: "Distance (\(draft.distanceUnit))"),
                    placeholder: draft.sport == .swim ? "1500" : "10,0",
                    text: $draft.distanceText,
                    keyboard: .decimalPad
                )
            }
            if draft.measuresElevation {
                SharpitFormField(String(localized: "Dénivelé positif (m)"), placeholder: "120", text: $draft.elevationText, keyboard: .numberPad)
            }
            if draft.measuresHeartRate {
                SharpitFormField(String(localized: "FC moyenne (bpm)"), placeholder: "145", text: $draft.avgHrText, keyboard: .numberPad)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .transition(.opacity)
    }

    private var effortCard: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            rpeSlider
            feelingRow
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private var rpeSlider: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                SharpitFieldLabel(String(localized: "Effort perçu (RPE)"))
                Spacer()
                if let rpe = draft.rpe {
                    Text("\(rpe)/10 · \(ActivityDraft.effortWord(rpe))")
                        .font(SharpitTypography.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.numericText(value: Double(rpe)))
                    Button {
                        SharpitMotion.run(SharpitMotion.selection) { draft.rpe = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .buttonStyle(.sharpitPressable)
                    .accessibilityLabel("Effacer l’effort")
                } else {
                    Text("Non précisé")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Slider(
                value: Binding(
                    get: { Double(draft.rpe ?? 5) },
                    set: { value in
                        let next = Int(value.rounded())
                        guard next != draft.rpe else { return }
                        draft.rpe = next
                        SharpitHaptics.play(.notch(major: next % 5 == 0))
                    }
                ),
                in: 1...10,
                step: 1
            )
            .tint(SharpitColor.highlight)
            .opacity(draft.rpe == nil ? 0.5 : 1)
            .accessibilityLabel("Effort perçu")
            .accessibilityValue(draft.rpe.map { "\($0) sur 10" } ?? String(localized: "Non précisé"))
        }
    }

    private var feelingRow: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(String(localized: "Ressenti"))
            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(SessionFeeling.allCases) { feeling in
                    let isSelected = draft.feeling == feeling
                    Button {
                        SharpitMotion.run(SharpitMotion.selection) {
                            draft.feeling = isSelected ? nil : feeling
                        }
                    } label: {
                        Text(feeling.emoji)
                            .font(.system(size: 26))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(
                                isSelected ? SharpitColor.highlight : SharpitColor.analysisSurfaceAlt,
                                in: RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                            )
                            .scaleEffect(isSelected ? 1.06 : 1)
                    }
                    .buttonStyle(.sharpitPressable)
                    .accessibilityLabel(feeling.storedValue)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            if let feeling = draft.feeling {
                Text("\(feeling.storedValue) — \(feeling.hint)")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .transition(.opacity)
            }
        }
        .animation(SharpitMotion.selection, value: draft.feeling)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitFormField(String(localized: "Titre (facultatif)"), placeholder: draft.sport.label, text: $draft.title)
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitFieldLabel(String(localized: "Notes"))
                TextField("Ce qu’il faut retenir de la séance", text: $draft.notes, axis: .vertical)
                    .font(SharpitTypography.body)
                    .lineLimit(3...8)
                    .padding(.vertical, SharpitSpacing.sm)
                    .sharpitFieldWell()
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
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
