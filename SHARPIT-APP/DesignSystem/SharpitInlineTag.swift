import SwiftUI

/// A word set in a session's meta line to say what kind of session it is — « Brick », « Clé ».
/// The eyebrow's face on a faint primary capsule: read with the line, never louder than the title.
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
            .foregroundStyle(SharpitColor.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(SharpitColor.primary.opacity(0.12), in: Capsule())
    }
}
