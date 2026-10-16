import SwiftUI

/// A word set in a session's meta line to say what kind of session it is — « Brick », « Clé ».
/// The lime pill, small: read with the line, never louder than the title.
struct SharpitInlineTag: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(SharpitColor.highlightForeground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(SharpitColor.highlight, in: Capsule())
    }
}
