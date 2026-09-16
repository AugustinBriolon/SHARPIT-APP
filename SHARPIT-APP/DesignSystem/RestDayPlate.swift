import SwiftUI

/// Intentional rest-day evidence — fills the void so a rest day reads as Twin decision, not empty UI.
struct RestDayPlate: View {
    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.xs) {
            Image(systemName: "moon.zzz.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Repos")
                    .font(.headline)
                Text("Le Twin valide la récupération — pas de séance prévue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Repos. Le Twin valide la récupération — pas de séance prévue.")
    }
}
