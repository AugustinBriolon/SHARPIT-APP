import SwiftUI

/// Paramètres → Pages et widgets: one switch per part of SharpIt. Off, a feature disappears
/// from every place it shows — said exactly under each switch — and its data is kept, so turning
/// it back on shows everything as it was. Saved to the account, so the web follows.
struct FeaturesView: View {
    let store: FeatureStore
    let tokenProvider: () async throws -> String

    var body: some View {
        List {
            SharpitListIntro("Masque ce que tu n'utilises pas. Tes données restent enregistrées : tout revient tel quel quand tu réactives.")
            Section {
                ForEach(SharpitFeature.allCases) { feature in
                    Toggle(isOn: binding(feature)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(SharpitTypography.bodyEmphasis)
                                Text(feature.detail)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            SharpitRowIcon(symbol: feature.symbolName)
                        }
                    }
                    .tint(SharpitColor.primary)
                }
            } footer: {
                if let error = store.saveError {
                    SharpitListFooter(error, tone: SharpitColor.signalRisk)
                } else {
                    SharpitListFooter("Un widget déjà posé sur l'écran d'accueil indique qu'il est masqué ; retire-le depuis l'écran d'accueil.")
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("Pages et widgets")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(_ feature: SharpitFeature) -> Binding<Bool> {
        Binding(
            get: { store.isOn(feature) },
            set: { on in
                SharpitHaptics.play(.soft)
                Task { await store.set(feature, on: on, tokenProvider: tokenProvider) }
            }
        )
    }
}
