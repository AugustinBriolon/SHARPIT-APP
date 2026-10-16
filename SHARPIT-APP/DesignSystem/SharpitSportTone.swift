import SwiftUI

/// Sport identity — Ink & Lime (ADR-085): a sport is told by its icon, never its colour.
///
/// Every sport resolves to the same monochrome treatment, so the mapping stays the one
/// place feature views ask, and a sport can never drift back into its own hue.
enum SharpitSportTone {
    /// Line, stroke and glyph colour — ink on light, near-white on dark.
    static func accent(for type: V1ActivityType) -> Color {
        SharpitColor.foreground
    }

    /// Text in the sport's slot — same as any foreground text.
    static func label(for type: V1ActivityType) -> Color {
        SharpitColor.foreground
    }

    /// Chip fill — the neutral chip.
    static func background(for type: V1ActivityType) -> Color {
        SharpitColor.chipSurface
    }

    /// Chips carry no outline.
    static func border(for type: V1ActivityType) -> Color {
        .clear
    }

    /// Icon tile fill — ink squircle on light, graphite on dark.
    static func tile(for type: V1ActivityType) -> Color {
        SharpitColor.inkSurface
    }

    /// Glyph on the icon tile — lime.
    static func tileGlyph(for type: V1ActivityType) -> Color {
        SharpitColor.inkAccent
    }

    // MARK: - String-keyed entry point

    /// Some payloads carry the sport as free text (`SessionCardModel.sport`) rather than
    /// as a typed enum, so the label is matched before falling back to `.other`.
    static func accent(for sport: String) -> Color {
        accent(for: type(forLabel: sport))
    }

    static func label(for sport: String) -> Color {
        label(for: type(forLabel: sport))
    }

    static func background(for sport: String) -> Color {
        background(for: type(forLabel: sport))
    }

    static func border(for sport: String) -> Color {
        border(for: type(forLabel: sport))
    }

    /// The glyph for a sport named in prose, resolved through the same mapping as its
    /// colour so a card cannot show one sport's icon in another's hue.
    static func symbolName(for sport: String) -> String {
        type(forLabel: sport).symbolName
    }

    // MARK: - Mapping

    private static func type(forLabel sport: String) -> V1ActivityType {
        V1ActivityType(sportLabel: sport)
    }
}
