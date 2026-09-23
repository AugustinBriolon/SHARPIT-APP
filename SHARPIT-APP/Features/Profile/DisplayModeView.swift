import SwiftData
import SwiftUI

/// Réglages → Densité de lecture: how much of the technical layer the athlete wants shown
/// (ADR 0006).
///
/// Saves on the tap, with no form to submit, as the web's Personnalisation picker does. The
/// density lives on the profile rather than on the handset, so choosing expert here is
/// choosing it everywhere.
struct DisplayModeView: View {
    @State private var store: AthleteProfileStore
    let displayMode: DisplayModeStore

    init(
        client: any AthleteProfileServing,
        displayMode: DisplayModeStore,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        _store = State(initialValue: AthleteProfileStore(
            client: client,
            tokenProvider: tokenProvider,
            modelContext: modelContext
        ))
        self.displayMode = displayMode
    }

    var body: some View {
        Group {
            switch store.phase {
            case .unauthorized:
                SharpitStateMessage.sessionExpired()
            case .failed(let message):
                SharpitStateMessage.failed(message) { Task { await store.load() } }
            case .idle, .loading, .loaded:
                list
            }
        }
        .navigationTitle("Densité de lecture")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.phase != .loaded { await store.load() } }
    }

    private var list: some View {
        List {
            SharpitListIntro("Ce que SHARPIT affiche, pas ce qu'il mesure. Les deux lectures partent des mêmes calculs.")
            if store.phase == .loaded {
                Section {
                    choice(
                        title: "Essentiel",
                        detail: "Ce qui s'est passé, ce que ça a coûté, quoi faire ensuite.",
                        example: "Charge 78 · ressenti solide",
                        isExpert: false
                    )
                    choice(
                        title: "Expert",
                        detail: "Ajoute la couche technique : TSS, IF, CTL/ATL/TSB, zones, découplage.",
                        example: "78 TSS · IF 0,82 · TSB −12",
                        isExpert: true
                    )
                } footer: {
                    saveStatus
                }
                .sharpitListRows()
            } else {
                DisplayModeSkeleton()
            }
        }
        .sharpitGroupedList()
    }

    @ViewBuilder
    private var saveStatus: some View {
        if store.isSaving {
            SharpitListFooter("Enregistrement…")
        } else if let saveError = store.saveError {
            SharpitListFooter(saveError, tone: SharpitColor.signalRisk)
        }
    }

    /// One row of a single-choice group, marked with a check as the system's own settings do.
    private func choice(title: String, detail: String, example: String, isExpert: Bool) -> some View {
        let isSelected = store.isExpertReading == isExpert
        return Button {
            Task { await select(isExpert) }
        } label: {
            DisplayModeChoiceRow(title: title, detail: detail, example: example, isSelected: isSelected)
        }
        .disabled(store.isSaving)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Tells the shared store what the profile now holds, so every surface reading the
    /// density follows without a second network read.
    private func select(_ isExpert: Bool) async {
        guard store.isExpertReading != isExpert else { return }
        await store.setExpertReading(isExpert)
        displayMode.adopt(isExpert: store.isExpertReading)
    }
}

/// The row's content, shared with the skeleton so the two cannot drift apart.
private struct DisplayModeChoiceRow: View {
    let title: String
    let detail: String
    let example: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(detail)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(example)
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }
}

/// Two choice rows, shaped like the real ones, before the profile answers (`docs/adr/0008`).
private struct DisplayModeSkeleton: View {
    var body: some View {
        Section {
            DisplayModeChoiceRow(
                title: "Essentiel",
                detail: "Ce qui s'est passé, ce que ça a coûté, quoi faire ensuite.",
                example: "Charge 78 · ressenti solide",
                isSelected: false
            )
            DisplayModeChoiceRow(
                title: "Expert",
                detail: "Ajoute la couche technique : TSS, IF, CTL/ATL/TSB, zones, découplage.",
                example: "78 TSS · IF 0,82 · TSB −12",
                isSelected: false
            )
        }
        .sharpitListRows()
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
