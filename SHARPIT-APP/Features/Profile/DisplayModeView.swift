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
        tokenProvider: @escaping () async throws -> String
    ) {
        _store = State(initialValue: AthleteProfileStore(client: client, tokenProvider: tokenProvider))
        self.displayMode = displayMode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                Text("Ce que SHARPIT affiche, pas ce qu'il mesure. Les deux lectures partent des mêmes calculs.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Densité de lecture")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.phase != .loaded { await store.load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView("Lecture du profil…")
                .frame(maxWidth: .infinity)
        case .unauthorized:
            Label("Session expirée. Reconnecte-toi.", systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(SharpitColor.signalCaution)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(SharpitColor.signalCaution)
        case .loaded:
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
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
                if store.isSaving {
                    Label("Enregistrement…", systemImage: "arrow.triangle.2.circlepath")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                } else if let saveError = store.saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
            }
        }
    }

    private func choice(title: String, detail: String, example: String, isExpert: Bool) -> some View {
        let isSelected = store.isExpertReading == isExpert
        return Button {
            Task { await select(isExpert) }
        } label: {
            HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                    .accessibilityHidden(true)
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
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(isSelected ? .panel : .panelAlt)
        }
        .buttonStyle(.sharpitPressable)
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
