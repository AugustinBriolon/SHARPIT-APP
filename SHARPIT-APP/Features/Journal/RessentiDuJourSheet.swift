import SwiftUI

/// Résumé half-sheet: « Comment tu te sens ce matin ? »
///
/// One answer is enough: five named steps (`RessentiStepPicker`), the chosen one lime. Energy,
/// body and stress, and a note for the coach, wait under « Ajouter un détail » in the same picker
/// with their own words; opening them switches the detent to `.large`.
///
/// « Enregistrer » is optimistic: the sheet closes at once; the host clears the
/// morning-feel badge. Server confirmation finalises; a refusal reopens with the
/// draft and `RessentiDuJourStore.saveFailureMessage`.
struct RessentiDuJourSheet: View {
    @State private var store: RessentiDuJourStore
    @State private var detent: PresentationDetent = .medium

    /// Fired on tap — host closes the sheet and clears the badge before the network returns.
    let onOptimisticClose: () -> Void
    /// Fired only after the server confirms.
    let onSaved: (V1WellnessVerdictSummary?) -> Void
    /// Fired when the write fails for good — host restores badge and reopens.
    let onSaveFailed: () -> Void
    let onDismissLater: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?

    init(
        client: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        athleteId: String,
        trainingDayId: String = TrainingDayId.today(),
        local: WellnessCheckInLocalStore = .shared,
        initialFailureMessage: String? = nil,
        onOptimisticClose: @escaping () -> Void = {},
        onSaved: @escaping (V1WellnessVerdictSummary?) -> Void,
        onSaveFailed: @escaping () -> Void = {},
        onDismissLater: @escaping () -> Void = {}
    ) {
        _store = State(
            initialValue: RessentiDuJourStore(
                client: client,
                tokenProvider: tokenProvider,
                athleteId: athleteId,
                trainingDayId: trainingDayId,
                local: local,
                initialFailureMessage: initialFailureMessage
            )
        )
        self.onOptimisticClose = onOptimisticClose
        self.onSaved = onSaved
        self.onSaveFailed = onSaveFailed
        self.onDismissLater = onDismissLater
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                    header

                    RessentiStepPicker(
                        steps: SessionFeeling.allCases.map { ($0.rawValue, $0.storedValue) },
                        selection: store.feeling?.rawValue
                    ) { raw in
                        store.feeling = SessionFeeling(rawValue: raw)
                        store.persistDraft()
                    }

                    details

                    if case .failed(let message) = store.phase {
                        Text(message)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalCaution)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.bottom, SharpitSpacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(SharpitCanvasBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard") {
                        store.dismissForLater()
                        onDismissLater()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBar
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .sharpitSheet()
        .onChange(of: store.detailsExpanded) { _, expanded in
            if expanded {
                detent = .large
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.md) {
            SharpitIconTile(symbol: "sun.horizon")
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text("Comment tu te sens ce matin ?")
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Ta réponse affine le verdict du jour.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    /// Energy, body and stress, then the note: one tap away, never in the way of the answer.
    private var details: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            Button {
                withAnimation(SharpitMotion.reveal) { store.detailsExpanded.toggle() }
                store.persistDraft()
            } label: {
                HStack(spacing: SharpitSpacing.sm) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Ajouter un détail")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Text("Énergie, corps, stress, un mot pour le coach")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .rotationEffect(.degrees(store.detailsExpanded ? 180 : 0))
                }
                .padding(SharpitSpacing.cardPadding)
                .contentShape(.rect)
                .sharpitSurface(.panel)
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityValue(store.detailsExpanded ? "Ouvert" : "Fermé")

            if store.detailsExpanded {
                ForEach([WellnessDimension.energy, .soreness, .stress], id: \.self) { dimension in
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        Text(dimension.title)
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        RessentiStepPicker(
                            steps: WellnessScore.allCases.map { ($0.rawValue, dimension.label(for: $0)) },
                            selection: binding(for: dimension)?.rawValue
                        ) { raw in
                            if let score = WellnessScore(rawValue: raw) {
                                set(score, for: dimension)
                                store.persistDraft()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    Text("Un mot pour le coach")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    TextField("Ta nuit, une sensation particulière…", text: $store.notes, axis: .vertical)
                        .lineLimit(2...4)
                        .font(SharpitTypography.body)
                        .padding(SharpitSpacing.cardPadding)
                        .sharpitSurface(.panel)
                        .onChange(of: store.notes) { _, _ in store.persistDraft() }
                }
            }
        }
    }

    private func binding(for dimension: WellnessDimension) -> WellnessScore? {
        switch dimension {
        case .mood: nil
        case .energy: store.energy
        case .soreness: store.soreness
        case .stress: store.stress
        }
    }

    private func set(_ score: WellnessScore, for dimension: WellnessDimension) {
        switch dimension {
        case .mood: break
        case .energy: store.energy = score
        case .soreness: store.soreness = score
        case .stress: store.stress = score
        }
    }

    private var saveBar: some View {
        SharpitPrimaryButton(
            title: store.canSubmit ? "Enregistrer" : "Choisis ton ressenti",
            isBusy: store.phase == .submitting
        ) {
            save()
        }
        .disabled(!store.canSubmit)
        .opacity(store.canSubmit ? 1 : 0.4)
        .accessibilityHint(store.canSubmit ? "Enregistre ton ressenti du matin" : "Choisis d'abord comment tu te sens")
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.vertical, SharpitSpacing.sm)
    }

    /// Closes at once; the write continues behind. Input stays in the protected draft file.
    private func save() {
        let started = store.submitOptimistic(
            onConfirmed: { verdict in
                onSaved(verdict)
                toastCenter?.show(
                    "Ressenti noté ✓",
                    symbol: "checkmark.circle.fill",
                    tone: .success,
                    autoDismissAfter: 2.5
                )
            },
            onFailed: {
                onSaveFailed()
            }
        )
        guard started else { return }
        onOptimisticClose()
        dismiss()
    }
}

/// Five named steps in a row: the number, its word under it. The chosen one is lime; the others
/// are white tiles. No hue per step — a feeling is not a warning (ADR-085).
struct RessentiStepPicker: View {
    let steps: [(value: Int, label: String)]
    let selection: Int?
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: SharpitSpacing.xs) {
            ForEach(steps, id: \.value) { step in
                let isOn = step.value == selection
                Button {
                    withAnimation(SharpitMotion.selection) { onPick(step.value) }
                } label: {
                    VStack(spacing: SharpitSpacing.xxs) {
                        Text("\(step.value)")
                            .font(SharpitTypography.data)
                            .monospacedDigit()
                        Text(step.label)
                            .font(SharpitTypography.system(size: 11, weight: .semibold, relativeTo: .caption2))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isOn ? SharpitColor.highlightForeground : SharpitColor.foreground)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .padding(.horizontal, 2)
                    .sharpitConcentricBackground(isOn ? SharpitColor.highlight : SharpitColor.card, minimum: SharpitRadius.tile)
                    .sharpitShadow(.control)
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel("\(step.value), \(step.label)")
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }
}
