import SwiftUI

/// A word set in a session's meta line to say what kind of session it is — « Brick », « Clé ».
/// The coach's mark, small, in the Pro status set: read with the line, never louder than the title.
struct SharpitInlineTag: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(SharpitTypography.system(size: 12, weight: .semibold, relativeTo: .caption2))
            .foregroundStyle(SharpitColor.statusProForeground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(SharpitColor.statusPro, in: Capsule())
            .overlay(Capsule().strokeBorder(SharpitColor.statusProBorder, lineWidth: 1))
    }
}
