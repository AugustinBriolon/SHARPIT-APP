import SwiftUI

/// A section marker: caption size, slate, sentence case — and, heading a section of a Clinique
/// list (`sharpitGroupedList`), that section's title.
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

    @Environment(\.sharpitSectionTitles) private var isSectionTitle

    var body: some View {
        if isSectionTitle {
            // A list section opens on its title, as every Clinique page does.
            Text(text)
                .font(SharpitTypography.sectionTitle)
                .foregroundStyle(SharpitColor.foreground)
                .textCase(nil)
                .padding(.top, SharpitSpacing.xs)
                .accessibilityAddTraits(.isHeader)
        } else {
            caption
        }
    }

    private var caption: some View {
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
