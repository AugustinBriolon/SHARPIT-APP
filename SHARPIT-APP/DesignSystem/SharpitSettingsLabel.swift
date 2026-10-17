import SwiftUI

/// A settings row's label: the ink tile with its lime glyph, the title, and what the row holds
/// right now under it. Inside a `NavigationLink`, a `Toggle` or a `Button` of a grouped list — the
/// list draws the chevron, the switch and the hairlines (`docs/adr/0008`).
struct SharpitSettingsLabel: View {
    let symbol: String
    let title: String
    var detail: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                if let detail {
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
        } icon: {
            SharpitRowIcon.tile(symbol)
        }
    }
}

extension SharpitRowIcon {
    /// The settings rows' icon: the ink tile, lime glyph (ADR-085).
    static func tile(_ symbol: String) -> SharpitRowIcon {
        SharpitRowIcon(symbol: symbol, background: SharpitColor.inkSurface)
    }
}
