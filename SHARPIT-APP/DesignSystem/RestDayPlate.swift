import SwiftUI

/// Intentional rest-day evidence — fills the void so a rest day reads as Twin decision, not empty UI.
struct RestDayPlate: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: SharpitTokens.tileSize, height: SharpitTokens.tileSize)
                .background(SharpitColor.tile, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Repos")
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                Text("Le Twin valide la récupération. Pas de séance prévue.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, SharpitSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}
