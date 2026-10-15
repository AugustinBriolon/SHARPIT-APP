import SwiftUI

/// Résumé half-sheet: « Comment tu te sens ce matin ? »
///
/// Reuses `SubjectiveScale` + `RatingGrid` (post-strength rating) directly — no fork.
/// Extra journal scales stay collapsed under « Ajouter un détail »; expanding them
/// switches the detent to `.large`.
///
/// « Enregistrer » is optimistic: the sheet closes at once; the host clears the
/// morning-feel badge. Server confirmation finalises; a refusal reopens with the
/// draft and `RessentiDuJourStore.saveFailureMessage`.
struct RessentiDuJourSheet: View {
    @State private var store: RessentiDuJourStore
    @State private var detent: PresentationDetent = .medium
    @State private var saveSucceeded = false

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
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    Text("Comment tu te sens ce matin ?")
                        .font(SharpitTypography.cardTitle)
                        .tracking(SharpitTypography.cardTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    SubjectiveScale(
                        title: "Ressenti",
                        value: store.feeling?.rawValue,
                        outOf: 5,
                        caption: store.feeling?.hint ?? "1 très mal · 5 très bien",
                        tone: store.feeling.map(SessionFeedbackTone.feeling)
                    ) {
                        RatingGrid(
                            values: SessionFeeling.allCases.map(\.rawValue),
                            selection: store.feeling?.rawValue,
                            tone: { SessionFeedbackTone.feeling(SessionFeeling(rawValue: $0) ?? .okay) }
                        ) { raw in
                            if let feeling = SessionFeeling(rawValue: raw) {
                                store.feeling = feeling
                                store.persistDraft()
                            }
                        }
                    }

                    detailsDisclosure

                    if case .failed(let message) = store.phase {
                        Text(message)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalCaution)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(SharpitSpacing.pageInset)
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
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBar
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .sharpitSheet()
        .sensoryFeedback(.success, trigger: saveSucceeded)
        .onChange(of: store.detailsExpanded) { _, expanded in
            if expanded {
                detent = .large
            }
        }
    }

    @ViewBuilder
    private var detailsDisclosure: some View {
        DisclosureGroup(isExpanded: $store.detailsExpanded) {
            VStack(spacing: SharpitSpacing.sm) {
                ForEach([WellnessDimension.energy, .soreness, .stress], id: \.self) { dimension in
                    detailRow(dimension)
                }

                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    Text("Note pour le coach (optionnel)")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    TextField("Détail sur ta nuit, sensation particulière…", text: $store.notes, axis: .vertical)
                        .lineLimit(2...4)
                        .font(SharpitTypography.body)
                        .padding(SharpitSpacing.sm)
                        .sharpitSurface(.panel)
                        .onChange(of: store.notes) { _, _ in store.persistDraft() }
                }
            }
            .padding(.top, SharpitSpacing.sm)
        } label: {
            Text("Ajouter un détail")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
        }
        .tint(SharpitColor.primary)
        .onChange(of: store.detailsExpanded) { _, _ in store.persistDraft() }
    }

    private func detailRow(_ dimension: WellnessDimension) -> some View {
        let selected = binding(for: dimension)
        return VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SubjectiveScale(
                title: dimension.title,
                value: selected?.rawValue,
                outOf: 5,
                caption: selected.map { dimension.label(for: $0) } ?? dimension.hint,
                tone: selected.map { SessionFeedbackTone.feeling(SessionFeeling(rawValue: $0.rawValue) ?? .okay) }
            ) {
                RatingGrid(
                    values: WellnessScore.allCases.map(\.rawValue),
                    selection: selected?.rawValue,
                    tone: { SessionFeedbackTone.feeling(SessionFeeling(rawValue: $0) ?? .okay) }
                ) { raw in
                    if let score = WellnessScore(rawValue: raw) {
                        set(score, for: dimension)
                        store.persistDraft()
                    }
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
        VStack(spacing: SharpitSpacing.xs) {
            if !store.canSubmit {
                Text("Note ton ressenti")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Button {
                save()
            } label: {
                HStack(spacing: SharpitSpacing.xs) {
                    if store.phase == .submitting {
                        ProgressView()
                            .tint(SharpitColor.primaryForeground)
                    }
                    Text("Enregistrer")
                        .font(SharpitTypography.bodyEmphasis)
                }
                .foregroundStyle(SharpitColor.primaryForeground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(
                    SharpitColor.primary,
                    in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                )
                .sharpitShadow(.control)
            }
            .buttonStyle(.sharpitPressable)
            .disabled(!store.canSubmit)
            .opacity(store.canSubmit ? 1 : 0.45)
            .accessibilityHint(store.canSubmit ? "Enregistre ton ressenti du matin" : "Note ton ressenti d’abord")
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.sm)
        .padding(.bottom, SharpitSpacing.sm)
        .background(.bar)
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
        saveSucceeded = true
        onOptimisticClose()
        dismiss()
    }
}
