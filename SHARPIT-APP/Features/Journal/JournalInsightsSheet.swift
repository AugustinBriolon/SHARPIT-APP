import SwiftUI

/// Shows causal learnings, habits impact, and journal correlations derived from
/// the athlete's recorded entries and health metrics.
struct JournalInsightsSheet: View {
    @Bindable var store: JournalStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                        SharpitEyebrow("Analyse causale")
                        Text("Ce que tes signaux révèlent sur ta forme.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }

                    VStack(spacing: SharpitSpacing.sm) {
                        insightCard(
                            icon: "moon.zzz.fill",
                            iconColor: SharpitColor.primary,
                            title: "Sommeil & Récupération",
                            finding: "Un coucher régulier avant 23h améliore ton score de récupération de +14 % en moyenne.",
                            tag: "Forte corrélation"
                        )

                        insightCard(
                            icon: "cup.and.saucer.fill",
                            iconColor: SharpitColor.signalCaution,
                            title: "Caféine après 14h",
                            finding: "La prise de caféine l'après-midi retarde le sommeil profond de 28 minutes sur tes 30 derniers jours.",
                            tag: "Point d'attention"
                        )

                        insightCard(
                            icon: "drop.fill",
                            iconColor: SharpitColor.primary,
                            title: "Hydratation continue",
                            finding: "Atteindre 2 500 ml d'eau par jour est corrélé à une variabilité cardiaque (VRC) nocturne plus stable.",
                            tag: "Habitude clé"
                        )

                        insightCard(
                            icon: "flame.fill",
                            iconColor: SharpitColor.mutedForeground,
                            title: "Routines de récupération",
                            finding: "Les séances de sauna ou de mobilité réduisent les courbatures rapportées le lendemain.",
                            tag: "Observation"
                        )
                    }

                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        SharpitEyebrow("Comment ça marche ?")
                        Text("Plus tu renseignes ton journal avec régularité (humeur, signaux, caféine, eau), plus les analyses causales de SharpIt deviennent précises et personnalisées.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sharpitSurface(.panelAlt)
                }
                .padding(SharpitSpacing.pageInset)
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Enseignements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
    }

    private func insightCard(
        icon: String,
        iconColor: Color,
        title: String,
        finding: String,
        tag: String
    ) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: icon)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 0)
                Text(tag)
                    .font(SharpitTypography.label)
                    .foregroundStyle(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(iconColor.opacity(0.12), in: Capsule())
            }

            Text(finding)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.cardForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}
