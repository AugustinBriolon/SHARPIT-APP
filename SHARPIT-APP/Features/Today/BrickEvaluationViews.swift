import SwiftUI

/// The brick's own verdict, under its legs: unrated, the value becomes the invitation to rate.
struct BrickEvaluationTile: View {
    let store: BrickEvaluationStore
    let action: () -> Void

    var body: some View {
        ReadoutTile(caption: String(localized: "Évaluation du brick"), action: action) {
            switch store.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .unavailable(let message):
                Text(message)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            case .ready where store.isEmpty:
                Label("Évaluer l'enchaînement", systemImage: "plus.circle.fill")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
            case .ready:
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.lg) {
                    reading(String(localized: "Effort"), value: store.rpe, outOf: 10)
                    reading(String(localized: "Transitions"), value: store.transitionRating, outOf: 5)
reading(String(localized: "Ressenti"), value: store.feeling?.rawValue, outOf: 5)
                }
            }
        }
        .disabled(store.phase != .ready)
        .accessibilityHint("Ouvre l'évaluation du brick")
    }

    private func reading(_ label: String, value: Int?, outOf: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ScaleReadout(value: value, outOf: outOf)
            Text(label)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
        }
    }
}

/// Three scales and a note about the chain, no buttons: each tap saves, closing writes the rest.
struct BrickEvaluationSheet: View {
    @Bindable var store: BrickEvaluationStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    CliniqueScale(
                        title: String(localized: "Effort global"),
                        values: Array(1...10),
                        selection: store.rpe,
                        word: SessionEffortReadout.word,
                        ends: (String(localized: "Très facile"), String(localized: "Maximal"))
                    ) { store.setRPE($0) }
                    // The brick entire, transitions included — not each sport.
                    CliniqueScale(
                        title: String(localized: "Transitions"),
                        values: BrickTransitionRating.allCases.map(\.rawValue),
                        selection: store.transitionRating,
                        ends: (String(localized: "Ratées"), String(localized: "Fluides"))
                    ) { store.setTransitionRating($0) }
                    CliniqueScale(
                        title: String(localized: "Ressenti"),
                        values: SessionFeeling.allCases.map(\.rawValue),
                        selection: store.feeling?.rawValue,
                        word: { SessionFeeling(rawValue: $0)?.storedValue },
                        ends: (SessionFeeling.veryBad.storedValue, SessionFeeling.veryGood.storedValue)
                    ) { raw in
                        if let feeling = SessionFeeling(rawValue: raw) { store.setFeeling(feeling) }
                    }

                    notesField

                    SaveStatusLine(status: store.status)
                }
                .padding(SharpitSpacing.pageInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Comment s'est passé le brick ?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .sharpitSheet()
        .onDisappear { Task { await store.flush() } }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(String(localized: "Notes"))
            TextField(
                String(localized: "Jambes en sortie de vélo, ravitaillement, matériel…"),
                text: Binding(get: { store.notes }, set: { store.setNotes($0) }),
                axis: .vertical
            )
            .lineLimit(3...6)
            .font(SharpitTypography.body)
            .padding(SharpitSpacing.sm)
            .sharpitSurface(.panel)
        }
    }
}
