import StoreKit
import SwiftUI

/// Paramètres → SharpIt Pro: where the athlete stands, what Pro adds over the free version, and
/// the App Store's own subscription sheet to subscribe, restore or manage.
///
/// The perks are the web's (`/api/v1/pro`), never a copy: the same list on both platforms,
/// worded once. Buying goes through `SubscriptionStoreView`, the system paywall — prices, trial
/// and legal lines come from the App Store and stay correct in every storefront.
struct ProView: View {
    let store: ProStore

    @State private var managesSubscription = false
    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                statusCard
                    .revealed(hasAppeared, index: 0)

                if !store.isPro {
                    paywall
                        .revealed(hasAppeared, index: 1)
                }

                perkGroup("Réservé à Pro", perks: store.proPerks, badge: "Pro", highlighted: true)
                    .revealed(hasAppeared, index: 2)
                perkGroup("Déjà inclus", perks: store.includedPerks, badge: "Inclus", highlighted: false)
                    .revealed(hasAppeared, index: 3)
                perkGroup("Bientôt", perks: store.plannedPerks, badge: "Bientôt", highlighted: false)
                    .revealed(hasAppeared, index: 4)

                actions
                    .revealed(hasAppeared, index: 5)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .background(SharpitCanvasBackground())
        .navigationTitle("SharpIt Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .manageSubscriptionsSheet(isPresented: $managesSubscription)
        .onChange(of: managesSubscription) { _, isShowing in
            // Back from the App Store's sheet: the web has heard any change by now, or will.
            if !isShowing { Task { await store.load() } }
        }
        .onAppear { hasAppeared = true }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Ton palier", systemImage: "sparkle")
            Text(store.isPro ? "SharpIt Pro" : "Gratuit")
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
                .contentTransition(.opacity)
            Text(ProReadout.status(store.pro?.subscription, isPro: store.isPro))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.75))
            if let message = store.message {
                Text(message)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.highlight)
                    .transition(.opacity)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
        .redacted(reason: store.phase == .loading ? .placeholder : [])
        .animation(SharpitMotion.reveal, value: store.message)
    }

    /// The App Store's paywall for the SharpIt Pro products, carrying the account token so the
    /// purchase is tied to this athlete.
    private var paywall: some View {
        SubscriptionStoreView(productIDs: SharpitProProduct.all)
            .subscriptionStoreControlStyle(.prominentPicker)
            .subscriptionStoreButtonLabel(.multiline)
            .storeButton(.hidden, for: .cancellation)
            .storeButton(.visible, for: .restorePurchases)
            .inAppPurchaseOptions { _ in
                store.appAccountToken.map { [.appAccountToken($0)] } ?? []
            }
            .onInAppPurchaseCompletion { _, result in
                if case .success(.success(let verification)) = result {
                    await store.handle(verification)
                }
            }
            .tint(SharpitColor.primary)
            .frame(minHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: SharpitRadius.panelLarge, style: .continuous))
    }

    @ViewBuilder
    private func perkGroup(_ title: String, perks: [V1ProPerk], badge: String, highlighted: Bool) -> some View {
        if !perks.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow(title)
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    ForEach(perks) { perk in
                        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                            Image(systemName: highlighted ? "checkmark.seal.fill" : "circle.dashed")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(highlighted ? SharpitColor.primary : SharpitColor.mutedForeground)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: SharpitSpacing.xs) {
                                    Text(perk.title)
                                        .font(SharpitTypography.bodyEmphasis)
                                        .foregroundStyle(SharpitColor.foreground)
                                    Text(badge.uppercased())
                                        .font(SharpitTypography.label)
                                        .tracking(SharpitTypography.labelTracking)
                                        .foregroundStyle(highlighted ? SharpitColor.highlightForeground : SharpitColor.mutedForeground)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            highlighted ? SharpitColor.highlight : SharpitColor.analysisGrid.opacity(0.6),
                                            in: Capsule()
                                        )
                                }
                                Text(perk.description)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(SharpitSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sharpitSurface(.panel)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: SharpitSpacing.sm) {
            if store.isAppleSubscription {
                Button("Gérer mon abonnement") { managesSubscription = true }
                    .sharpitGlassButton(prominent: false)
                    .frame(maxWidth: .infinity)
            }
            if store.isPro {
                Button {
                    Task { await store.restore() }
                } label: {
                    if store.isRestoring {
                        ProgressView()
                    } else {
                        Text("Restaurer mes achats")
                    }
                }
                .font(SharpitTypography.meta.weight(.semibold))
                .foregroundStyle(SharpitColor.primary)
                .disabled(store.isRestoring)
            }
            Text("L'abonnement est géré par l'App Store et se renouvelle automatiquement, sauf résiliation au moins 24 h avant la fin de la période en cours.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: SharpitSpacing.md) {
                Link("Conditions d'utilisation", destination: LegalDocument.terms.url)
                Link("Confidentialité", destination: LegalDocument.privacy.url)
            }
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
