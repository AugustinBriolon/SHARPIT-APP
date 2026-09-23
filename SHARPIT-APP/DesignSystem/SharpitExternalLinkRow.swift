import SwiftUI

/// A list row that leaves the app for a page on the web.
///
/// A `Link` rather than a button calling `openURL`, so VoiceOver announces it as a link and
/// the outward arrow is not the only sign that it leaves (`docs/adr/0004`).
struct SharpitExternalLinkRow: View {
    let title: String
    let symbol: String
    var background: Color? = nil
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack {
                // The title is coloured on its own: a `Link` tints its whole label, and a
                // tinted title would read as different from its neighbours' plain ones.
                Label {
                    Text(title)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                } icon: {
                    SharpitRowIcon(symbol: symbol, background: background)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .accessibilityHidden(true)
            }
        }
    }
}
