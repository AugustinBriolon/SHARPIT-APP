import SwiftUI

struct SharpitEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(SharpitTypography.eyebrow())
            .tracking(SharpitTypography.eyebrowTracking)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}
