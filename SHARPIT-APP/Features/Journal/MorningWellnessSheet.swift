import SwiftUI

/// The morning ressenti, one scale per step.
struct MorningWellnessSheet: View {
    @State private var store: MorningWellnessStore
    /// The mood label the check-in produced, so the journal can echo it.
    let onCompleted: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        client: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        trainingDayId: String,
        onCompleted: @escaping (String) -> Void
    ) {
        _store = State(
            initialValue: MorningWellnessStore(
                client: client,
                tokenProvider: tokenProvider,
                trainingDayId: trainingDayId
            )
        )
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(SharpitCanvasBackground())
                .navigationTitle("Ressenti du matin")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where store.picks.isEmpty:
            ContentUnavailableView {
                Label("Ressenti indisponible", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
        case .ready, .saving, .failed:
            steps
        }
    }

    private var steps: some View {
        VStack(spacing: SharpitSpacing.lg) {
            WellnessStepDots(count: store.stepCount, current: store.step)

            if case .failed(let message) = store.phase {
                Text(message)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalCaution)
            }

            if let dimension = store.dimension {
                WellnessScaleStep(dimension: dimension, selected: store.picks[dimension]) { score in
                    store.pick(score, for: dimension)
                }
            } else {
                WellnessNoteStep(notes: Binding(get: { store.notes }, set: { store.notes = $0 }))
            }

            Spacer(minLength: 0)
            controls
        }
        .padding(SharpitSpacing.pageInset)
        .opacity(store.phase == .saving ? 0.6 : 1)
        .disabled(store.phase == .saving)
    }

    private var controls: some View {
        HStack(spacing: SharpitSpacing.sm) {
            if store.step > 0 {
                Button("Précédent") { store.step -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
            if store.isOnNoteStep {
                Button("Enregistrer") {
                    Task {
                        guard let label = await store.submit() else { return }
                        onCompleted(label)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canSubmit)
            } else {
                Button("Suivant") { store.step += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canGoForward)
            }
        }
        .tint(SharpitColor.primary)
    }
}

private struct WellnessStepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: SharpitSpacing.xxs) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? SharpitColor.primary : SharpitColor.analysisBorder)
                    .frame(width: index == current ? 20 : 6, height: 6)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityLabel("Étape \(current + 1) sur \(count)")
    }
}

private struct WellnessScaleStep: View {
    let dimension: WellnessDimension
    let selected: WellnessScore?
    let onPick: (WellnessScore) -> Void

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            VStack(spacing: SharpitSpacing.xxs) {
                Text(dimension.title)
                    .font(SharpitTypography.sectionTitle)
                    .foregroundStyle(SharpitColor.foreground)
                Text(dimension.hint)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: SharpitSpacing.xs) {
                ForEach(WellnessScore.allCases) { score in
                    Button {
                        onPick(score)
                    } label: {
                        HStack(spacing: SharpitSpacing.sm) {
                            Text(dimension.label(for: score))
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.foreground)
                            Spacer(minLength: 0)
                            if selected == score {
                                Image(systemName: "checkmark")
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.primary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(SharpitSpacing.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .sharpitSurface(selected == score ? .panelAlt : .panel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == score ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }
}

private struct WellnessNoteStep: View {
    @Binding var notes: String

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            VStack(spacing: SharpitSpacing.xxs) {
                Text("Note")
                    .font(SharpitTypography.sectionTitle)
                    .foregroundStyle(SharpitColor.foreground)
                Text("Optionnel. Un détail pour le coach si besoin.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            TextEditor(text: $notes)
                .font(SharpitTypography.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(SharpitSpacing.xs)
                .sharpitSurface(.panel)
                .accessibilityLabel("Note pour le coach")
        }
    }
}
