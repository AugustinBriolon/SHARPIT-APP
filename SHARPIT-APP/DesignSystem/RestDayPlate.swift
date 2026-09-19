import SwiftUI

/// Intentional rest-day evidence — fills the void so a rest day reads as Twin decision, not empty UI.
struct RestDayPlate: View {
    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Image(systemName: "moon.zzz.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(SharpitColor.mutedForeground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text("Repos")
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                Text("Le Twin valide la récupération — pas de séance prévue.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Repos. Le Twin valide la récupération — pas de séance prévue.")
    }
}
