import SwiftUI

/// The brick's own verdict, under its legs: unrated, the value becomes the invitation to rate.
struct BrickEvaluationTile: View {
    let store: BrickEvaluationStore
    let action: () -> Void

    var body: some View {
        ReadoutTile(caption: "Évaluation du brick", action: action) {
            switch store.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .unavailable(let message):
                Text(message)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            case .ready where store.isEmpty:
                Label("Évaluer l'enchaînement", systemImage: "plus.circle.fill")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
            case .ready:
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.lg) {
                    reading("Effort", value: store.rpe, outOf: 10, tone: store.rpe.map(SessionFeedbackTone.effort))
                    reading("Transitions", value: store.transitionRating, outOf: 5, tone: nil)
                    reading(
                        "Ressenti",
                        value: store.feeling?.rawValue,
                        outOf: 5,
                        tone: store.feeling.map(SessionFeedbackTone.feeling)
                    )
                }
            }
        }
        .disabled(store.phase != .ready)
        .accessibilityHint("Ouvre l'évaluation du brick")
    }

    private func reading(_ label: String, value: Int?, outOf: Int, tone: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ScaleReadout(value: value, outOf: outOf, tone: tone ?? SharpitColor.foreground)
            Text(label)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
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
                    SubjectiveScale(
                        title: "Effort global",
                        value: store.rpe,
                        outOf: 10,
                        caption: "Le brick entier, transitions comprises — pas chaque sport.",
                        tone: store.rpe.map(SessionFeedbackTone.effort)
                    ) {
                        RatingGrid(
                            values: Array(1...10),
                            selection: store.rpe,
                            tone: SessionFeedbackTone.effort
                        ) { store.setRPE($0) }
                    }

                    SubjectiveScale(
                        title: "Transitions",
                        value: store.transitionRating,
                        outOf: 5,
                        caption: store.transitionRating.flatMap(BrickTransitionRating.init(rawValue:))?.hint
                            ?? "1 ratées · 5 fluides",
                        tone: store.transitionRating.map { _ in SharpitColor.primary }
                    ) {
                        RatingGrid(
                            values: BrickTransitionRating.allCases.map(\.rawValue),
                            selection: store.transitionRating,
                            tone: { _ in SharpitColor.primary }
                        ) { store.setTransitionRating($0) }
                    }

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
                            if let feeling = SessionFeeling(rawValue: raw) { store.setFeeling(feeling) }
                        }
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
            SharpitEyebrow("Notes")
            TextField(
                "Jambes en sortie de vélo, ravitaillement, matériel…",
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
