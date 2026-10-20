import StoreKit
import SwiftUI

/// Modale d'offre SharpIt Pro présentée pour débloquer le plan et l'accès complet au coaching.
/// Respecte les principes Apple Design : fluidité, hiérarchie claire, fermeture facile en haut,
/// et un bouton unique « S'abonner » en bas.
struct SharpitProPaywallSheet: View {
    let store: ProStore
    var onSubscribed: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProductId = SharpitProProduct.yearly
    @State private var errorMessage: String? = nil

    private struct PerkItem: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
    }

    private let perks: [PerkItem] = [
        PerkItem(
            icon: "calendar.badge.clock",
            title: String(localized: "Plan adaptatif & sur-mesure"),
            description: String(localized: "Séances recalculées en continu selon ta forme, ta fatigue et tes imprévus.")
        ),
        PerkItem(
            icon: "bubble.left.and.text.bubble.right.fill",
            title: String(localized: "Coach IA disponible 24/7"),
            description: String(localized: "Pose toutes tes questions à un coach expert qui connaît l'historique de tes séances.")
        ),
        PerkItem(
            icon: "chart.xyaxis.line",
            title: String(localized: "Analyses de séance guidées"),
            description: String(localized: "Allures cibles, zones de FC, estimation de la charge et conseils post-effort.")
        ),
        PerkItem(
            icon: "sparkles.square.filled.on.square",
            title: String(localized: "Bilan hebdomadaire complet"),
            description: String(localized: "Synthèse de volume, sommeil et récupération, avec la semaine suivante prête à l'avance.")
        ),
        PerkItem(
            icon: "applewatch.radiowaves.left.and.right",
            title: String(localized: "Synchronisation montre & agenda"),
            description: String(localized: "Envoi direct de tes séances vers ton Apple Watch, Garmin et ton calendrier iPhone.")
        ),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            SharpitCanvasBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                    headerSection
                        .padding(.top, SharpitSpacing.xl)

                    perksSection

                    pricingSection
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.bottom, 120) // Espace pour l'action dock fixe
            }
            .scrollIndicators(.hidden)

            // Croix de fermeture en haut à droite avec hit-target tactile généreux
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionDock
        }
        .task {
            await store.loadProducts()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(width: 32, height: 32)
                    .background(SharpitColor.chipSurface, in: Circle())
            }
            .buttonStyle(.sharpitPressable)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(String(localized: "Fermer"))
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.sm)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
                SharpitEyebrow("SharpIt Pro")
            }

            Text("Libère tout ton potentiel")
                .font(SharpitTypography.pageTitle)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text("Applique ton plan d'entraînement sur-mesure et bénéficie d'un coaching intelligent adapté à chaque séance.")
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Perks

    private var perksSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Tout ce qui est inclus dans Pro")

            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                ForEach(perks) { perk in
                    HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                        Image(systemName: perk.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SharpitColor.primary)
                            .frame(width: 28, height: 28)
                            .background(SharpitColor.chipSurface, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(perk.title)
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.foreground)
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

    // MARK: - Pricing Cards

    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Choisis ta formule")

            VStack(spacing: SharpitSpacing.sm) {
                annualCard
                monthlyCard
            }
        }
    }

    private var annualCard: some View {
        let isSelected = selectedProductId == SharpitProProduct.yearly
        let yearlyProduct = store.storeProducts.first(where: { $0.id == SharpitProProduct.yearly })
        let priceText = yearlyProduct != nil ? "\(yearlyProduct!.displayPrice) / an" : "99,99 € / an"

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(SharpitMotion.selection) {
                selectedProductId = SharpitProProduct.yearly
            }
        } label: {
            HStack(spacing: SharpitSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.5))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: SharpitSpacing.xs) {
                        Text("Annuel")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)

                        Text("-17 % • 2 MOIS OFFERTS")
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.highlightForeground)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SharpitColor.highlight, in: Capsule())
                    }

                    Text("Soit 8,33 € / mois • Facturé une fois par an")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                Spacer()

                Text(priceText)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .fill(SharpitColor.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(isSelected ? SharpitColor.primary : SharpitColor.border.opacity(0.4), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var monthlyCard: some View {
        let isSelected = selectedProductId == SharpitProProduct.monthly
        let monthlyProduct = store.storeProducts.first(where: { $0.id == SharpitProProduct.monthly })
        let priceText = monthlyProduct != nil ? "\(monthlyProduct!.displayPrice) / mois" : "9,99 € / mois"

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(SharpitMotion.selection) {
                selectedProductId = SharpitProProduct.monthly
            }
        } label: {
            HStack(spacing: SharpitSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground.opacity(0.5))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Mensuel")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)

                    Text("Sans engagement, résiliable à tout moment")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                Spacer()

                Text(priceText)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .fill(SharpitColor.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(isSelected ? SharpitColor.primary : SharpitColor.border.opacity(0.4), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Dock (Uniquement le bouton S'abonner)

    private var bottomActionDock: some View {
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

            // Bouton unique "S'abonner" en bas de la modale
            SharpitPrimaryButton(
                title: store.isPurchasing ? String(localized: "Activation…") : String(localized: "S'abonner"),
                isBusy: store.isPurchasing
            ) {
                Task {
                    errorMessage = nil
                    let success = await store.purchase(productId: selectedProductId)
                    if success {
                        dismiss()
                        onSubscribed?()
                    } else if let msg = store.message {
                        errorMessage = msg
                    }
                }
            }

            legalFooter
        }
    }

    private var legalFooter: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Button {
                Task {
                    errorMessage = nil
                    await store.restore()
                    if store.isPro {
                        dismiss()
                        onSubscribed?()
                    } else if let msg = store.message {
                        errorMessage = msg
                    }
                }
            } label: {
                if store.isRestoring {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text("Restaurer mes achats")
                }
            }
            .font(SharpitTypography.meta.weight(.semibold))
            .foregroundStyle(SharpitColor.primary)
            .disabled(store.isRestoring || store.isPurchasing)
            .padding(.top, SharpitSpacing.xxs)

            Text("Renouvellement automatique, résiliable à tout moment.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)

            HStack(spacing: SharpitSpacing.md) {
                Link("Conditions d'utilisation", destination: LegalDocument.terms.url)
                Link("Confidentialité", destination: LegalDocument.privacy.url)
            }
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SharpitSpacing.xxs)
    }
}
