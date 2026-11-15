import SwiftUI

/// Simplified morning wellness & mood check-in drawer.
/// Presents all 4 dimensions on a single half-screen sheet with an intuitive 1–5 scale.
struct MorningWellnessSheet: View {
    @State private var store: MorningWellnessStore
    /// The mood label the check-in produced, so the journal can echo it.
    let onCompleted: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?

    init(
        client: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        trainingDayId: String,
        onSaved: @escaping @MainActor () -> Void = {},
        onCompleted: @escaping (String) -> Void
    ) {
        _store = State(
            initialValue: MorningWellnessStore(
                client: client,
                tokenProvider: tokenProvider,
                trainingDayId: trainingDayId,
                onSaved: onSaved
            )
        )
        self.onCompleted = onCompleted
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SharpitColor.card)
            .cliniqueSheetCross { dismiss() }
            .presentationDetents([.large])
            .sharpitSheet()
            .presentationDragIndicator(.visible)
            .task { await store.load() }
            .onChange(of: store.phase) { _, phase in
                if case .failed(let message) = phase, !store.picks.isEmpty {
                    toastCenter?.show(
                        message,
                        symbol: "exclamationmark.triangle.fill",
                        tone: .error,
                        autoDismissAfter: 3.5
                    )
                }
            }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            CliniqueSheetTitle(String(localized: "Humeur et ressenti"))
            Text("Quatre réponses, d'un glissement du doigt. Elles ajustent la séance du jour.")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            VStack(alignment: .leading, spacing: 24) {
                title
                ProgressView().frame(maxWidth: .infinity).padding(.top, SharpitSpacing.xl)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
        case .failed(let message) where store.picks.isEmpty:
            SharpitStateMessage.failed(message) { Task { await store.load() } }
                .embedded()
        case .ready, .failed:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    title.padding(.bottom, 4)
                    ForEach(WellnessDimension.allCases) { dimension in
                        WellnessDimensionRow(
                            dimension: dimension,
                            selected: store.picks[dimension],
                            onPick: { score in store.pick(score, for: dimension) }
                        )
                        CliniqueDivider()
                    }
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        SharpitFieldLabel(String(localized: "Un mot pour le coach (optionnel)"))
                        TextField("Détail sur ta nuit, sensation particulière…", text: $store.notes, axis: .vertical)
                            .lineLimit(2...3)
                            .font(SharpitTypography.body)
                            .padding(.vertical, SharpitSpacing.sm)
                            .sharpitFieldWell(isActive: !store.notes.isEmpty)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 30)
                .padding(.bottom, SharpitSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            // Docked, so « Enregistrer » is never cut by the sheet's height.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    guard let label = store.submit() else { return }
                    onCompleted(label)
                    dismiss()
                } label: {
                    Text("Enregistrer").frame(maxWidth: .infinity)
                }
                .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                .disabled(!store.canSubmit)
                .padding(.horizontal, 16)
                .padding(.vertical, SharpitSpacing.xs)
                .background(SharpitColor.card)
            }
        }
    }
}

/// One question of the check-in: its name, the word the answer stands for, one track to slide on.
struct WellnessDimensionRow: View {
    let dimension: WellnessDimension
    let selected: WellnessScore?
    let onPick: (WellnessScore) -> Void

    var body: some View {
        CliniqueScale(
            title: dimension.title,
            values: WellnessScore.allCases.map(\.rawValue),
            selection: selected?.rawValue,
            word: { WellnessScore(rawValue: $0).map(dimension.label(for:)) },
            ends: WellnessReadout.ends(dimension)
        ) { raw in
            if let score = WellnessScore(rawValue: raw) { onPick(score) }
        }
    }
}

nonisolated enum WellnessReadout {
    /// « Épuisé » and « Plein »: what the two ends of a question's scale stand for.
    static func ends(_ dimension: WellnessDimension) -> (low: String, high: String) {
        (dimension.label(for: .one), dimension.label(for: .five))
    }
}
