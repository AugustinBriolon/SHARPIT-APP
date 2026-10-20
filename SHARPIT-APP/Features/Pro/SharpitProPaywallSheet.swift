import StoreKit
import SwiftUI

/// SharpIt Pro's one paywall, from the onboarding's first week and from every teaser: the week
/// as a picture, three lines, two plans and one button. Every price is the App Store's — the
/// introductory offer only when StoreKit says this Apple Account can still take it.
struct SharpitProPaywallSheet: View {
    let store: ProStore
    /// The onboarding's preview week; nil draws the example week.
    var sessions: [V1GeneratedSession]? = nil
    var onSubscribed: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Namespace private var selectionRing
    @State private var selectedProductId: String?
    @State private var isEligibleForIntroOffer = false
    @State private var hasLoadedOffers = false
    @State private var hasAppeared = false
    @State private var errorMessage: String?

    private struct Perk: Identifiable {
        let id: String
        let text: String
    }

    private let perks = [
        Perk(id: "calendar", text: String(localized: "Ta semaine, écrite pour toi")),
        Perk(id: "arrow.triangle.2.circlepath", text: String(localized: "Elle s'adapte à ta vie")),
        Perk(id: "bubble.left.and.text.bubble.right", text: String(localized: "Un coach qui lit tes données")),
    ]

    private var monthly: Product? { store.storeProducts.first { $0.id == SharpitProProduct.monthly } }
    private var yearly: Product? { store.storeProducts.first { $0.id == SharpitProProduct.yearly } }
    private var selected: Product? { store.storeProducts.first { $0.id == selectedProductId } }

    /// The monthly intro offer, only once StoreKit has said this account may take it.
    private var introOffer: Product.SubscriptionOffer? {
        isEligibleForIntroOffer ? monthly?.subscription?.introductoryOffer : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                ProWeekHero(sessions: sessions)
                    .revealed(hasAppeared, index: 0)

                Text(sessions == nil ? String(localized: "Ton coach, ta semaine.") : String(localized: "Ta semaine est prête"))
                    .font(SharpitTypography.screenTitle)
                    .tracking(SharpitTypography.screenTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .revealed(hasAppeared, index: 1)

                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    ForEach(Array(perks.enumerated()), id: \.element.id) { index, perk in
                        HStack(spacing: SharpitSpacing.sm) {
                            SharpitIconTile(symbol: perk.id, size: 32)
                            Text(perk.text)
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.foreground)
                        }
                        .revealed(hasAppeared, index: 2 + index)
                    }
                }

                plans
                    .revealed(hasAppeared, index: 5)

                ProPerkGroup(title: String(localized: "Tout ce qui est inclus"), perks: store.proPerks, highlighted: true)
                    .revealed(hasAppeared, index: 6)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.xl + SharpitSpacing.sm)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .scrollIndicators(.hidden)
        .background(SharpitCanvasBackground())
        .overlay(alignment: .topTrailing) { closeButton }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionDock }
        .sharpitSheet()
        .onAppear { hasAppeared = true }
        .task { await loadOffers() }
        .task { if store.pro == nil { await store.load() } }
    }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        if let monthly, let yearly {
            VStack(spacing: SharpitSpacing.xs) {
                planCard(
                    yearly,
                    title: String(localized: "Annuel"),
                    price: String(localized: "\(yearly.displayPrice) / an"),
                    detail: String(localized: "soit \((yearly.price / 12).formatted(yearly.priceFormatStyle)) / mois"),
                    badge: ProPriceReadout.yearlySaving(monthly: monthly.price, yearly: yearly.price)
                )
                if let introOffer {
                    planCard(
                        monthly,
                        title: String(localized: "Mensuel"),
                        price: String(localized: "\(introOffer.displayPrice) le 1er mois"),
                        detail: String(localized: "puis \(monthly.displayPrice) / mois"),
                        badge: ProPriceReadout.percentOff(full: monthly.price, paid: introOffer.price)
                    )
                } else {
                    planCard(
                        monthly,
                        title: String(localized: "Mensuel"),
                        price: String(localized: "\(monthly.displayPrice) / mois"),
                        detail: String(localized: "Sans engagement"),
                        badge: nil
                    )
                }
            }
        } else if store.storeProducts.isEmpty, hasLoadedOffers {
            VStack(spacing: SharpitSpacing.xs) {
                Text("Impossible de charger les offres.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Button("Réessayer") { Task { await loadOffers() } }
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 140)
        }
    }

    private func planCard(_ product: Product, title: String, price: String, detail: String, badge: Int?) -> some View {
        let isSelected = selectedProductId == product.id
        return Button {
            withAnimation(SharpitMotion.selection) { selectedProductId = product.id }
        } label: {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: SharpitSpacing.xs) {
                        Text(title)
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        if let badge {
                            SharpitPill(String(localized: "−\(badge) %"), style: .lime)
                        }
                    }
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer(minLength: SharpitSpacing.xs)
                Text(price)
                    .font(SharpitTypography.system(size: 17, weight: .bold, relativeTo: .headline, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.trailing)
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity)
            .background(SharpitColor.card, in: RoundedRectangle(cornerRadius: SharpitRadius.row, style: .continuous))
            .overlay {
                // One ring that travels between the plans rather than two that blink.
                if isSelected {
                    RoundedRectangle(cornerRadius: SharpitRadius.row, style: .continuous)
                        .strokeBorder(SharpitColor.foreground, lineWidth: 2)
                        .matchedGeometryEffect(id: "ring", in: selectionRing)
                }
            }
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Actions

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 32, height: 32)
                .background(SharpitColor.chipSurface, in: Circle())
        }
        .buttonStyle(.sharpitPressable)
        .frame(minWidth: SharpitSpacing.minimumTouchTarget, minHeight: SharpitSpacing.minimumTouchTarget)
        .padding(.trailing, SharpitSpacing.xs)
        .padding(.top, SharpitSpacing.xs)
        .accessibilityLabel(String(localized: "Fermer"))
    }

    private var buttonTitle: String {
        if store.isPurchasing { return String(localized: "Activation…") }
        if selectedProductId == SharpitProProduct.monthly, let introOffer {
            return String(localized: "Commencer à \(introOffer.displayPrice)")
        }
        return String(localized: "S'abonner")
    }

    private var actionDock: some View {
        SharpitActionDock {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SharpitSpacing.sm)
                    .padding(.vertical, SharpitSpacing.xxs + 2)
                    .sharpitGlassCapsule()
                    .transition(.opacity)
            }
            SharpitPrimaryButton(title: buttonTitle, isBusy: store.isPurchasing) {
                Task { await purchase() }
            }
            .contentTransition(.numericText())
            .animation(SharpitMotion.selection, value: buttonTitle)
            // Never a purchase without the account token: Apple's notifications would not name the athlete.
            .disabled(selected == nil || !store.canPurchase || store.isPurchasing || store.isRestoring)

            legalFooter
        }
        .animation(SharpitMotion.fade, value: errorMessage)
    }

    private var legalFooter: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Text("Renouvellement automatique, résiliable à tout moment.")
                .multilineTextAlignment(.center)
            HStack(spacing: SharpitSpacing.md) {
                Button {
                    Task { await restore() }
                } label: {
                    if store.isRestoring { ProgressView().controlSize(.mini) } else { Text("Restaurer mes achats") }
                }
                .disabled(store.isRestoring || store.isPurchasing)
                Link("Conditions d'utilisation", destination: LegalDocument.terms.url)
                Link("Confidentialité", destination: LegalDocument.privacy.url)
            }
        }
        .font(SharpitTypography.meta)
        .foregroundStyle(SharpitColor.mutedForeground)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Work

    private func loadOffers() async {
        async let token: Void = store.ensureAppAccountToken()
        await store.loadProducts()
        await token
        if let subscription = monthly?.subscription, subscription.introductoryOffer != nil {
            isEligibleForIntroOffer = await subscription.isEligibleForIntroOffer
        }
        hasLoadedOffers = true
        guard selectedProductId == nil else { return }
        // The first month's discount is the hook while the account can take it; otherwise the
        // yearly plan, which costs the athlete least.
        selectedProductId = introOffer != nil ? SharpitProProduct.monthly : SharpitProProduct.yearly
    }

    private func purchase() async {
        guard let selectedProductId else { return }
        errorMessage = nil
        if await store.purchase(productId: selectedProductId) {
            dismiss()
            onSubscribed?()
        } else {
            errorMessage = store.message
        }
    }

    private func restore() async {
        errorMessage = nil
        await store.restore()
        if store.isPro {
            dismiss()
            onSubscribed?()
        } else {
            errorMessage = store.message
        }
    }
}
