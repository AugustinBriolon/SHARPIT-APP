import SwiftUI

/// Intentional rest-day evidence — fills the void so a rest day reads as Twin decision, not empty UI.
struct RestDayPlate: View {
    var body: some View {
        SharpitCardHeader(
            title: String(localized: "Repos"),
            symbol: "moon.zzz.fill",
            subtitle: String(localized: "Le Twin valide la récupération — pas de séance prévue."),
            showsChevron: false
        )
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Repos. Le Twin valide la récupération — pas de séance prévue.")
    }
}
