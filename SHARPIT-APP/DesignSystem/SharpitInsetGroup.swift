import SwiftUI

/// The rows that sit inside a card — exercises, sets, a day's items. They read straight on the
/// card, split by hairlines as Apple's grouped lists are, never boxed in a second card.
struct SharpitInsetGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().padding(.horizontal, SharpitSpacing.rowPaddingX)
                    }
                    row
                }
            }
        }
        // Rows pad themselves by rowPaddingX; pulling the group out by as much lines their
        // words up with the card's header.
        .padding(.horizontal, -SharpitSpacing.rowPaddingX)
    }
}

/// One row in an inset group: leading mark, a title, then a trailing readout.
struct SharpitInsetRow<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            leading
            Text(title)
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: SharpitSpacing.xs)
            trailing
                .fixedSize()
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .frame(minHeight: SharpitSpacing.rowHeight)
        .sharpitSurface(.row)
        .accessibilityElement(children: .combine)
    }
}

/// A figure with its unit muted beside it, at row size: « 3 590 kg », « 12 × ».
struct SharpitRowFigure: View {
    let value: String
    var unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(SharpitTypography.data)
                .foregroundStyle(SharpitColor.foreground)
            if let unit {
                Text(unit)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}
