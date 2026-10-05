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

/// A follow-up: how much it hurts today, what the athlete could do, a word if they want.
struct ZoneCheckinSheet: View {
    let zone: V1SensitiveZone
    let onSave: (ZoneCheckinDraft) async -> Bool

    @State private var draft = ZoneCheckinDraft()
    @State private var isSaving = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        SharpitFieldLabel("Douleur aujourd'hui")
                        ZoneSeverityScale(severity: $draft.severity)
                    }
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        SharpitFieldLabel("Ce que tu as pu faire")
                        ZoneImpactPicker(selection: $draft.functionalImpact)
                    }
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        SharpitFieldLabel("Un mot (facultatif)")
                        TextField("Après la sortie longue, au réveil…", text: $draft.comment, axis: .vertical)
                            .font(SharpitTypography.body)
                            .lineLimit(2...4)
                            .sharpitFieldWell()
                    }
                    if failed {
                        Text("L'enregistrement a échoué. Réessaie.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                }
                .padding(SharpitSpacing.pageInset)
            }
            .navigationTitle(zone.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        isSaving = true
                        Task {
                            let saved = await onSave(draft)
                            isSaving = false
                            if saved { dismiss() } else { failed = true }
                        }
                    }
                    .disabled(!draft.isComplete || isSaving)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }
}

/// 0 to 10 as eleven stops — a pain is reported, not measured. Unanswered until touched.
private struct ZoneSeverityScale: View {
    @Binding var severity: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: 4) {
                ForEach(0...10, id: \.self) { value in
                    let isSelected = severity == value
                    Button {
                        SharpitMotion.run(SharpitMotion.selection) { severity = value }
                    } label: {
                        Text("\(value)")
                            .font(SharpitTypography.meta.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                            .frame(maxWidth: .infinity, minHeight: SharpitSpacing.minimumTouchTarget)
                            .background(
                                RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                                    .fill(isSelected ? ZoneSeverityTint.color(value).opacity(value == 0 ? 1 : 0.9) : SharpitColor.analysisSurfaceAlt)
                            )
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) sur 10")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            HStack {
                Text("Aucune")
                Spacer()
                Text("Insupportable")
            }
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.mutedForeground)
        }
    }
}

private struct ZoneImpactPicker: View {
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ForEach(SensitiveZoneOptions.impacts) { option in
                OnboardingChoiceChip(title: option.label, isSelected: selection == option.value) {
                    selection = selection == option.value ? nil : option.value
                }
            }
        }
    }
}
