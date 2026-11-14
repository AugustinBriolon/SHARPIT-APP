import SwiftUI

/// A section marker: caption size, slate, sentence case.
///
/// An optional symbol sits with the words rather than on a line of its own: a section
/// needs one title, not a label above a second heading that says the same thing.
struct SharpitEyebrow: View {
    let text: String
    var systemImage: String?

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: SharpitSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
        }
    }
}
