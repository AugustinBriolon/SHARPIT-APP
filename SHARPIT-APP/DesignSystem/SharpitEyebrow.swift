import SwiftUI

/// `text-label` used as a section marker — uppercase, tracked, muted.
struct SharpitEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(SharpitTypography.eyebrow)
            .tracking(SharpitTypography.eyebrowTracking)
            .textCase(.uppercase)
            .foregroundStyle(SharpitColor.mutedForeground)
    }
}
