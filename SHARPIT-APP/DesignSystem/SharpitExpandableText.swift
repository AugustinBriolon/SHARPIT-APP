import SwiftUI

/// A text the athlete wrote, which may run long: six lines, then « Lire la suite » opens it whole.
struct SharpitExpandableText: View {
    let text: String
    @State private var isOpen = false

    /// shortcut: length decides whether the text is cut, not a measure of the laid-out lines;
    /// measure them if a short text with many line breaks ever shows without its button.
    static func runsLong(_ text: String) -> Bool {
        text.count > 320 || text.filter(\.isNewline).count > 5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text(text)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(isOpen ? nil : 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            if Self.runsLong(text) {
                Button(isOpen ? String(localized: "Réduire") : String(localized: "Lire la suite")) {
                    SharpitMotion.run { isOpen.toggle() }
                }
                .buttonStyle(CliniqueButtonStyle(kind: .plain))
            }
        }
    }
}
