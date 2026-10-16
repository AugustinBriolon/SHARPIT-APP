import SwiftUI

/// The Live Activities' shared look (ADR-085): an ink ground with white type and lime as the
/// only accent, so they read as SharpIt on any wallpaper and in both appearances — the way
/// Apple's own Timer and Fitness activities keep one dark ground with one tint.
enum LiveActivityStyle {
    static let ground = SharpitColor.inkSurface
    static let ink = SharpitColor.inkSurfaceForeground
    static let accent = SharpitColor.highlight
    /// Apple's lock-screen margin for an activity's content.
    static let margin: CGFloat = 16
}

/// The brand mark of an activity: a lime squircle with an ink glyph.
struct LiveActivityTile: View {
    let symbol: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(SharpitColor.highlightForeground)
            .frame(width: size, height: size)
            .background(LiveActivityStyle.accent, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Small lime label over a title: what the activity is doing right now.
struct LiveActivityEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(LiveActivityStyle.accent)
            .lineLimit(1)
    }
}
