import SwiftUI

/// The header every readout card on Résumé and Corps shares: a tinted round badge with its
/// symbol, the uppercase label, then an optional accessory and the disclosure chevron. One
/// component, so a badge, a tracking or a chevron can never drift a point between cards.
struct SharpitCardHeader<Accessory: View>: View {
    let title: String
    let symbol: String
    var tint: Color = SharpitColor.primary
    var showsChevron = true
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            Text(title)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.foreground.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 2)

            accessory()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension SharpitCardHeader where Accessory == EmptyView {
    init(title: String, symbol: String, tint: Color = SharpitColor.primary, showsChevron: Bool = true) {
        self.init(title: title, symbol: symbol, tint: tint, showsChevron: showsChevron) { EmptyView() }
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
                .font(.system(size: 11, weight: value == nil ? .medium : .regular))
                .foregroundStyle(SharpitColor.mutedForeground)
            if let value {
                Text("·")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(SharpitColor.secondary.opacity(0.55))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(SharpitColor.border.opacity(0.06), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
    }
}
