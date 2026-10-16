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
    private let badgeSize: CGFloat = 32

    var body: some View {
        if background != nil {
            // A badged row takes the brand's icon tile: ink, lime glyph (ADR-085).
            SharpitIconTile(symbol: symbol, size: badgeSize)
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
