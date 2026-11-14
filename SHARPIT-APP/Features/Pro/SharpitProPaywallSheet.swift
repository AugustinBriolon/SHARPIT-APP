import StoreKit
import SwiftUI

/// SharpIt Pro's one paywall, from the onboarding's first week and from every teaser, on its
/// mock-up (`docs/adr/0035`): what Pro is in a title, four lines, two plans and one button. Every
/// price is the App Store's — the introductory offer only when StoreKit says this Apple Account
/// can still take it.
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
        let pillar: CliniquePillar
        let title: String
        let detail: String
    }

    private let perks = [
        Perk(id: "bubble.left", pillar: .coach, title: String(localized: "Coach à la demande"), detail: String(localized: "Il répond avec ta nuit, ta charge et ton plan")),
        Perk(id: "calendar", pillar: .recovery, title: String(localized: "Plan qui se répare seul"), detail: String(localized: "Séance manquée, voyage, mauvaise nuit : il s'ajuste")),
        Perk(id: "flame", pillar: .nutrition, title: String(localized: "Lecture de ta nutrition"), detail: String(localized: "Ce qu'il te manque avant et après chaque séance")),
        Perk(id: "heart", pillar: .sleep, title: String(localized: "Âge biologique et bilan hebdo"), detail: String(localized: "Ta santé lue comme un check-up")),
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
            VStack(alignment: .leading, spacing: 0) {
                CliniqueStatusPill("SharpIt Pro", status: .pro)
                    .revealed(hasAppeared, index: 0)
                Text(sessions == nil ? String(localized: "Un coach qui lit tes données tous les matins") : String(localized: "Ta semaine est prête"))
                    .font(SharpitTypography.system(size: 30, weight: .semibold, relativeTo: .largeTitle))
                    .tracking(-0.6)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .revealed(hasAppeared, index: 1)
                Text("Tes données restent à toi et gratuites. Pro ajoute la lecture et les décisions.")
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .revealed(hasAppeared, index: 1)

                // The onboarding's own week, when there is one to show.
                if sessions != nil {
                    ProWeekHero(sessions: sessions)
                        .padding(.top, 20)
                        .revealed(hasAppeared, index: 2)
                }

                VStack(spacing: 0) {
                    ForEach(Array(perks.enumerated()), id: \.element.id) { index, perk in
                        CliniqueDivider()
                        HStack(spacing: 18) {
                            Image(systemName: perk.id)
                                .font(.system(size: 19, weight: .regular))
                                .foregroundStyle(perk.pillar.color)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(perk.title)
                                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                                    .foregroundStyle(SharpitColor.foreground)
                                Text(perk.detail)
                                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                                    .foregroundStyle(SharpitColor.slate)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 13)
                        .accessibilityElement(children: .combine)
                        .revealed(hasAppeared, index: 2 + index)
                    }
                }
                .padding(.top, 20)

                plans
                    .padding(.top, 20)
                    .revealed(hasAppeared, index: 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .scrollIndicators(.hidden)
        .cliniqueSheet(wash: .coach, height: 220)
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
            VStack(spacing: 10) {
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
                    .foregroundStyle(SharpitColor.slate)
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
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            withAnimation(SharpitMotion.selection) { selectedProductId = product.id }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.outline)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                    Text(detail)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
                Spacer(minLength: SharpitSpacing.xs)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(price)
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.trailing)
                    if let badge {
                        CliniqueStatusPill(String(localized: "− \(badge) %"), status: .good)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(SharpitColor.card, in: shape)
            .overlay(shape.strokeBorder(SharpitColor.divider, lineWidth: 1))
            .overlay {
                // One ring that travels between the plans rather than two that blink.
                if isSelected {
                    shape
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 44, height: 44)
                .background(SharpitColor.card, in: Circle())
                .overlay(Circle().strokeBorder(SharpitColor.divider, lineWidth: 1))
        }
        .buttonStyle(.sharpitPressable)
        .frame(minWidth: SharpitSpacing.minimumTouchTarget, minHeight: SharpitSpacing.minimumTouchTarget)
        .padding(.trailing, 22)
        .padding(.top, 14)
        .accessibilityLabel(String(localized: "Fermer"))
    }

    private var buttonTitle: String {
        if store.isPurchasing { return String(localized: "Activation…") }
        if selectedProductId == SharpitProProduct.monthly, let introOffer {
            return String(localized: "Commencer à \(introOffer.displayPrice)")
        }
        return String(localized: "Passer à Pro")
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
            Button { Task { await purchase() } } label: {
                Group {
                    if store.isPurchasing { ProgressView().tint(SharpitColor.primaryForeground) } else { Text(buttonTitle) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
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
                    if store.isRestoring { ProgressView().controlSize(.mini) } else { Text("Restaurer un achat").underline() }
                }
                .disabled(store.isRestoring || store.isPurchasing)
                Link(destination: LegalDocument.terms.url) { Text("Conditions").underline() }
                Link(destination: LegalDocument.privacy.url) { Text("Confidentialité").underline() }
            }
        }
        .font(SharpitTypography.meta)
        .foregroundStyle(SharpitColor.slate)
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
