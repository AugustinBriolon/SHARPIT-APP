import SwiftUI

/// A row's icon: the bare symbol in the brand tone, in a column of fixed width.
///
/// No badge behind it. A badge has to contain every symbol, and SF Symbols do not share a
/// footprint — `bicycle` is half again as wide as `target` at the same point size — so either
/// the wide ones break out of it or the narrow ones float in it. A bare glyph in a fixed
/// column is how the system's own lists align icons of different shapes: the column keeps the
/// titles on one vertical line, and `.imageScale(.medium)` keeps every glyph at the text's
/// optical size, scaling with Dynamic Type.
struct SharpitRowIcon: View {
    let symbol: String
    var tone: Color = SharpitColor.primary
    var background: Color? = nil

    @ScaledMetric(relativeTo: .body) private var column: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 15

    var body: some View {
        if let background {
            ZStack {
                RoundedRectangle(cornerRadius: badgeSize * 0.217, style: .continuous)
                    .fill(background)
                    .frame(width: badgeSize, height: badgeSize)

                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: badgeSize, height: badgeSize)
            .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.body)
                .imageScale(.medium)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tone)
                .frame(width: column)
                .accessibilityHidden(true)
        }
    }
}
