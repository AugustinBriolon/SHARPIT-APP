import SwiftUI

/// A settings row's label: the title, and what the row holds right now at the trailing edge —
/// no glyph, as the mock-up's tables (`docs/adr/0035`). Inside a `NavigationLink`, a `Toggle` or a `Button` of a grouped list — the
/// list draws the chevron, the switch and the hairlines (`docs/adr/0008`).
struct SharpitSettingsLabel: View {
    let title: String
    var detail: String?
    /// The page's glyph, so a row is told at a glance before its title is read.
    var symbol: String?

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            if let symbol { SharpitSettingsGlyph(symbol: symbol) }
            Text(title)
                .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
            }
        }
        .padding(.vertical, 3)
    }
}

/// A settings row's glyph: plain ink in a fixed column, so every title starts on the same line.
struct SharpitSettingsGlyph: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(SharpitColor.foreground)
            .frame(width: 28)
            .accessibilityHidden(true)
    }
}

extension SharpitRowIcon {
    /// The settings rows' icon: the ink tile, lime glyph (ADR-085).
    static func tile(_ symbol: String) -> SharpitRowIcon {
        SharpitRowIcon(symbol: symbol, background: SharpitColor.inkSurface)
    }
}
