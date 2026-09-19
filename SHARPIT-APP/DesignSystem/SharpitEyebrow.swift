import SwiftUI

/// `text-label` used as a section marker — uppercase, tracked, muted.
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
        HStack(spacing: SharpitSpacing.xxs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(SharpitTypography.eyebrow)
                .tracking(SharpitTypography.eyebrowTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }
}
