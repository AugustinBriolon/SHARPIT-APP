import SwiftUI

/// A titled card of the web's perks (`V1ProPerk`), shared by `ProView` and the paywall.
struct ProPerkGroup: View {
    let title: String
    let perks: [V1ProPerk]
    /// Tags each row; nil when the whole group is already one tier (the paywall).
    var badge: String?
    var highlighted = false

    var body: some View {
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
                                    if let badge {
                                        badgePill(badge)
                                    }
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

    private func badgePill(_ badge: String) -> some View {
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
}
