import SwiftUI

/// The grey group that holds white rows inside a card — exercises, sets, a day's items
/// (ADR-085). Its rows are separated by air, never by a line.
struct SharpitInsetGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: SharpitSpacing.rowGap) { content }
            .padding(SharpitSpacing.insetPadding)
            .sharpitSurface(.panelAlt)
    }
}

/// One white row in an inset group: leading mark, a title, then a trailing readout.
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
