import SwiftUI

/// Declares a zone, or edits one. The body part is picked from the web's list, so the plan can
/// always check it spares the zone; a free-text one stays possible, flagged as unchecked.
struct SensitiveZoneFormSheet: View {
    @State var draft: SensitiveZoneDraft
    let bodyParts: [String]
    let isNew: Bool
    let onSave: (SensitiveZoneDraft) async -> Bool

    @State private var writesOwnPart = false
    @State private var isSaving = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    private let grid = Array(repeating: GridItem(.flexible(), spacing: SharpitSpacing.xs), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    choices("Qu'est-ce que c'est ?", SensitiveZoneOptions.categories, selection: $draft.category)
                    bodyPartPicker
                    choices("Quel côté ?", SensitiveZoneOptions.sides, selection: $draft.side)
                    severityPicker
                    impactPicker
                    SharpitFormField("Nom (facultatif)", placeholder: draft.resolvedTitle, text: $draft.title)
                    descriptionField
                    Toggle(isOn: $draft.affectsTraining) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prise en compte dans le plan")
                                .font(SharpitTypography.bodyEmphasis)
                            Text("Le coach adapte les séances à cette zone.")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                    .tint(SharpitColor.primary)
                    if failed {
                        Text("L'enregistrement a échoué. Réessaie.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                }
                .padding(SharpitSpacing.pageInset)
            }
            .navigationTitle(isNew ? "Déclarer une zone" : "Modifier la zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Ajouter" : "Enregistrer") { save() }
                        .disabled(!draft.isComplete || isSaving)
                }
            }
            .onAppear { writesOwnPart = draft.bodyPart == nil && !draft.customBodyPart.isEmpty }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await onSave(draft)
            isSaving = false
            if saved { dismiss() } else { failed = true }
        }
    }

    private func choices(
        _ question: String,
        _ options: [SensitiveZoneOptions.Choice],
        selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(question)
            LazyVGrid(columns: grid, spacing: SharpitSpacing.xs) {
                ForEach(options) { option in
                    OnboardingChoiceChip(title: option.label, isSelected: selection.wrappedValue == option.value) {
                        selection.wrappedValue = option.value
                    }
                }
            }
        }
    }

    private var bodyPartPicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Où ?")
            LazyVGrid(columns: grid, spacing: SharpitSpacing.xs) {
                ForEach(bodyParts, id: \.self) { part in
                    OnboardingChoiceChip(title: part, isSelected: draft.bodyPart == part && !writesOwnPart) {
                        writesOwnPart = false
                        draft.bodyPart = part
                    }
                }
                OnboardingChoiceChip(title: "Autre…", isSelected: writesOwnPart) {
                    writesOwnPart = true
                    draft.bodyPart = nil
                }
            }
            if writesOwnPart {
                TextField("Ex. : plexus", text: $draft.customBodyPart)
                    .font(SharpitTypography.body)
                    .sharpitFieldWell()
                Text("Une zone hors liste reste suivie, mais le plan ne peut pas vérifier qu'il l'épargne.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var severityPicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(SensitiveZoneOptions.isCorrective(draft.category) ? "Gêne ressentie" : "Douleur aujourd'hui")
            ZoneSeverityScale(severity: Binding(get: { draft.severity }, set: { draft.severity = $0 ?? 0 }))
        }
    }

    private var impactPicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Ce que tu peux encore faire")
            ZoneImpactPicker(selection: $draft.functionalImpact)
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Notes (facultatif)")
            TextField("Quand ça apparaît, ce qui soulage…", text: $draft.description, axis: .vertical)
                .font(SharpitTypography.body)
                .lineLimit(3...6)
                .sharpitFieldWell()
        }
    }
}

/// A follow-up after a session (or from Santé): how much it hurts, what still works, a word.
/// Opens as a medium drawer — one question, one reading — not a full-page form.
struct ZoneCheckinSheet: View {
    let zone: V1SensitiveZone
    /// Asked above the scales when the check-in follows a session.
    var prompt: String? = nil
    let onSave: (ZoneCheckinDraft) async -> Bool

    @State private var draft = ZoneCheckinDraft()
    @State private var isSaving = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    private var isCorrective: Bool { SensitiveZoneOptions.isCorrective(zone.category) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    header
                    severityBlock
                    impactBlock
                    commentBlock
                    if failed {
                        Text("L'enregistrement a échoué. Réessaie.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.top, SharpitSpacing.md)
                .padding(.bottom, SharpitSpacing.xl)
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
            .navigationTitle(zone.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            SharpitEyebrow(zone.place)
            Text(prompt ?? (isCorrective ? "Comment ça va aujourd'hui ?" : "Comment va la douleur ?"))
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var severityBlock: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .lastTextBaseline) {
                SharpitEyebrow(isCorrective ? "Gêne" : "Douleur")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(draft.severity.map(String.init) ?? "—")
                        .font(SharpitTypography.gaugeScore)
                        .foregroundStyle(draft.severity.map(ZoneSeverityTint.color) ?? SharpitColor.mutedForeground)
                        .contentTransition(.numericText())
                    Text("/10")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            ZoneSeverityScale(severity: $draft.severity)
            Text(draft.severity.map(ZoneSeverityTint.caption) ?? "Touche une valeur")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .contentTransition(.opacity)
        }
        .animation(SharpitMotion.selection, value: draft.severity)
    }

    private var impactBlock: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Ce que tu as pu faire")
            ZoneImpactPicker(selection: $draft.functionalImpact)
        }
    }

    private var commentBlock: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Un mot (facultatif)")
            TextField("Après la séance, au réveil…", text: $draft.comment, axis: .vertical)
                .font(SharpitTypography.body)
                .lineLimit(2...4)
                .sharpitFieldWell()
        }
    }

    private var saveBar: some View {
        Button {
            guard !isSaving else { return }
            isSaving = true
            Task {
                let saved = await onSave(draft)
                isSaving = false
                if saved { dismiss() } else { failed = true }
            }
        } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Text(isSaving ? "Enregistrement…" : "Enregistrer")
            }
            .font(SharpitTypography.bodyEmphasis)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                draft.isComplete ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.35),
                in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
            )
        }
        .buttonStyle(.sharpitPressable)
        .disabled(!draft.isComplete || isSaving)
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.vertical, SharpitSpacing.sm)
        .background(.ultraThinMaterial)
    }
}

/// 0 to 10 in two comfortable rows — a pain is reported, not measured. Unanswered until touched.
private struct ZoneSeverityScale: View {
    @Binding var severity: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            severityRow(0...5)
            severityRow(6...10)
            HStack {
                Text("Aucune")
                Spacer()
                Text("Insupportable")
            }
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.mutedForeground)
        }
    }

    private func severityRow(_ values: ClosedRange<Int>) -> some View {
        HStack(spacing: SharpitSpacing.xs) {
            ForEach(Array(values), id: \.self) { value in
                let isSelected = severity == value
                Button {
                    SharpitMotion.run(SharpitMotion.selection) { severity = value }
                } label: {
                    Text("\(value)")
                        .font(SharpitTypography.data)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                                .fill(isSelected ? ZoneSeverityTint.color(value) : SharpitElevatedColor.panelOnSheet)
                                .sharpitShadow(.control)
                        )
                        .scaleEffect(isSelected ? 1.04 : 1)
                        .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel("\(value) sur 10")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

private struct ZoneImpactPicker: View {
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ForEach(SensitiveZoneOptions.impacts) { option in
                let isSelected = selection == option.value
                Button {
                    SharpitMotion.run(SharpitMotion.selection) {
                        selection = isSelected ? nil : option.value
                    }
                } label: {
                    HStack {
                        Text(option.label)
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                    }
                    .padding(.horizontal, SharpitSpacing.cardPadding)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                            .fill(isSelected ? SharpitColor.primary.opacity(0.10) : SharpitElevatedColor.panelOnSheet)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                            .strokeBorder(isSelected ? SharpitColor.primary.opacity(0.35) : .clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

