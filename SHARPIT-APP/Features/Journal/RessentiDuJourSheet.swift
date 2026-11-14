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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
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
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SharpitColor.card)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveBar
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Ton ressenti ce matin")
                .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Ta réponse ajuste la séance du jour.")
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .foregroundStyle(SharpitColor.slate)
        }
    }

    /// Energy, body and stress, then the note: one tap away, never in the way of the answer.
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            CliniqueDivider()
            Button {
                withAnimation(SharpitMotion.reveal) { store.detailsExpanded.toggle() }
                store.persistDraft()
            } label: {
                HStack(spacing: SharpitSpacing.sm) {
                    Text("Ajouter un détail")
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SharpitColor.slate)
                        .rotationEffect(.degrees(store.detailsExpanded ? 180 : 0))
                }
                .padding(.vertical, 18)
                .contentShape(.rect)
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityValue(store.detailsExpanded ? String(localized: "Ouvert") : String(localized: "Fermé"))
            .accessibilityHint("Énergie, corps, stress, un mot pour le coach")

            if store.detailsExpanded {
                ForEach([WellnessDimension.energy, .soreness, .stress], id: \.self) { dimension in
                    CliniqueDivider()
                    RessentiScaleRow(
                        title: dimension.title,
                        word: binding(for: dimension).map { dimension.label(for: $0) },
                        score: binding(for: dimension)?.rawValue
                    ) { raw in
                        if let score = WellnessScore(rawValue: raw) {
                            set(score, for: dimension)
                            store.persistDraft()
                        }
                    }
                }
                CliniqueDivider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Un mot pour le coach")
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.slate)
                    TextField("Ta nuit, une sensation particulière…", text: $store.notes, axis: .vertical)
                        .lineLimit(2...4)
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .padding(16)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SharpitColor.divider, lineWidth: 1))
                        .onChange(of: store.notes) { _, _ in store.persistDraft() }
                }
                .padding(.top, 16)
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
        VStack(spacing: 4) {
            Button(action: save) {
                Group {
                    if store.phase == .submitting {
                        ProgressView().tint(SharpitColor.primaryForeground)
                    } else {
                        Text(store.canSubmit ? String(localized: "Enregistrer") : String(localized: "Choisis ton ressenti"))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
            .disabled(!store.canSubmit)
            .accessibilityHint(store.canSubmit ? String(localized: "Enregistre ton ressenti du matin") : String(localized: "Choisis d'abord comment tu te sens"))
            Button("Plus tard") {
                store.dismissForLater()
                onDismissLater()
                dismiss()
            }
            .buttonStyle(CliniqueButtonStyle(kind: .plain))
        }
        .padding(.horizontal, 24)
        .padding(.top, SharpitSpacing.xs)
        .background(SharpitColor.card)
    }

    /// Closes at once; the write continues behind. Input stays in the protected draft file.
    private func save() {
        let started = store.submitOptimistic(
            onConfirmed: { verdict in
                onSaved(verdict)
                toastCenter?.show(
                    String(localized: "Ressenti noté ✓"),
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

/// Five named steps in a row: as many bars as the step, its word under them. The chosen one is
/// ink; the others are bordered tiles. No hue per step — a feeling is not a warning.
struct RessentiStepPicker: View {
    let steps: [(value: Int, label: String)]
    let selection: Int?
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(steps, id: \.value) { step in
                let isOn = step.value == selection
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                Button {
                    withAnimation(SharpitMotion.selection) { onPick(step.value) }
                } label: {
                    VStack(spacing: 8) {
                        HStack(alignment: .bottom, spacing: 2.5) {
                            ForEach(0..<step.value, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 1.5).frame(width: 3.5, height: 5 + CGFloat(index) * 4)
                            }
                        }
                        .frame(height: 22, alignment: .bottom)
                        .accessibilityHidden(true)
                        Text(step.label)
                            .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isOn ? SharpitColor.primaryForeground : SharpitColor.foreground)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .padding(.horizontal, 2)
                    .background(isOn ? SharpitColor.primary : .clear, in: shape)
                    .overlay(shape.strokeBorder(SharpitColor.divider, lineWidth: isOn ? 0 : 1))
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel("\(step.value), \(step.label)")
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }
}

/// A detail on five dashes: its name, the word for where it stands, and the dashes to tap.
struct RessentiScaleRow: View {
    let title: String
    let word: String?
    let score: Int?
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: SharpitSpacing.xs)
            if let word {
                Text(word)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
            }
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { step in
                    Button {
                        withAnimation(SharpitMotion.selection) { onPick(step) }
                    } label: {
                        Capsule()
                            .fill(step <= (score ?? 0) ? SharpitColor.foreground : SharpitColor.tile)
                            .frame(width: 24, height: 7)
                            .padding(.horizontal, 2.5)
                            .frame(height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(step) sur 5")
                    .accessibilityAddTraits(step == score ? [.isSelected] : [])
                }
            }
        }
        .padding(.vertical, 6)
    }
}
