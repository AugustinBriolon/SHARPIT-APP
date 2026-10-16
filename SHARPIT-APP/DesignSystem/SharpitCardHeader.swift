import SwiftUI

/// The header every card shares: the ink icon tile, a title and a muted subtitle, then an
/// optional accessory (a pill, a figure) and the disclosure chevron. One component, so a tile,
/// a weight or a gap can never drift a point between cards.
struct SharpitCardHeader<Accessory: View>: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    /// shortcut: ignored since ADR-085 (tiles are always ink + lime); drop with the screen sweep.
    var tint: Color = SharpitColor.primary
    var showsChevron = true
    /// Half-width cards take a smaller tile so the title keeps its room.
    var isCompact = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? SharpitSpacing.xxs + 2 : SharpitSpacing.sm) {
            SharpitIconTile(symbol: symbol, size: isCompact ? 30 : SharpitTokens.tileSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(isCompact ? SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline) : SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(isCompact ? 0.75 : 0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: isCompact ? 2 : SharpitSpacing.xs)

            accessory()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension SharpitCardHeader where Accessory == EmptyView {
    init(
        title: String,
        symbol: String,
        subtitle: String? = nil,
        tint: Color = SharpitColor.primary,
        showsChevron: Bool = true,
        isCompact: Bool = false
    ) {
        self.init(
            title: title,
            symbol: symbol,
            subtitle: subtitle,
            tint: tint,
            showsChevron: showsChevron,
            isCompact: isCompact
        ) { EmptyView() }
    }
}

/// The context line at a card's foot: a muted lead and an emphasised figure, in the capsule
/// the overnight gauges use.
struct SharpitTelemetryCapsule: View {
    let lead: String
    var value: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(lead)
                .font(.system(size: 13, weight: value == nil ? .medium : .regular))
                .foregroundStyle(SharpitColor.mutedForeground)
            if let value {
                Text("·")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(SharpitColor.chipSurface)
        )
        .accessibilityElement(children: .combine)
    }
}
