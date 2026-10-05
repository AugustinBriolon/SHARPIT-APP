import SwiftUI

/// Paramètres → Pages et widgets: one row per part of SharpIt, saying whether it shows. Each
/// opens its own page — what it looks like, why follow it, where it shows — with the switch.
struct FeaturesView: View {
    let store: FeatureStore
    let tokenProvider: () async throws -> String

    var body: some View {
        List {
            Section {
                ForEach(SharpitFeature.allCases) { feature in
                    NavigationLink {
                        FeatureDetailView(feature: feature, store: store, tokenProvider: tokenProvider)
                    } label: {
                        LabeledContent {
                            Text(store.isOn(feature) ? "Affiché" : "Masqué")
                                .foregroundStyle(store.isOn(feature) ? SharpitColor.mutedForeground : SharpitColor.signalCaution)
                        } label: {
                            Label {
                                Text(feature.title).font(SharpitTypography.bodyEmphasis)
                            } icon: {
                                SharpitRowIcon(symbol: feature.symbolName)
                            }
                        }
                    }
                }
            } footer: {
                SharpitListFooter("Masque ce que tu n'utilises pas. Tes données restent enregistrées : tout revient tel quel quand tu réactives.")
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("Pages et widgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One part of SharpIt: its rendering, drawn by the app's own components on example figures,
/// why follow it, where it shows, and the switch.
struct FeatureDetailView: View {
    let feature: SharpitFeature
    let store: FeatureStore
    let tokenProvider: () async throws -> String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                FeatureShowcase(feature: feature)
                    .allowsHitTesting(false)
                    .opacity(store.isOn(feature) ? 1 : 0.45)
                    .animation(SharpitMotion.selection, value: store.isOn(feature))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Aperçu de \(feature.title)")

                Toggle(isOn: binding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Afficher \(feature.title)")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Text(store.isOn(feature) ? "Visible dans l'app et ses widgets." : "Masqué partout. Tes données sont gardées.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .tint(SharpitColor.primary)
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)

                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    SharpitEyebrow("Pourquoi le suivre")
                    Text(feature.why)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    SharpitEyebrow("Où il apparaît")
                    ForEach(feature.places, id: \.self) { place in
                        Label(place, systemImage: "checkmark")
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.foreground)
                    }
                    if feature == .nutrition || feature == .health || feature == .regularity {
                        Text("Un widget déjà posé sur l'écran d'accueil indique qu'il est masqué ; retire-le depuis l'écran d'accueil.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, SharpitSpacing.xxs)
                    }
                }
            }
            .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { store.isOn(feature) },
            set: { on in
                Task { await store.set(feature, on: on, tokenProvider: tokenProvider) }
            }
        )
    }
}
