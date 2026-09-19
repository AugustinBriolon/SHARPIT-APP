import SwiftUI

/// Sport identity — one chromatic family per activity type, exported from the web.
///
/// The web assigns these in `SPORT_IDENTITY_HEX`: orange run, emerald bike, sky swim,
/// rose strength, teal triathlon, amber hike, brand green for anything else. Lime Pulse is
/// never reused here — the highlight stays product punctuation, not a sport.
///
/// This is the only place the mapping exists. Feature views used to carry their own
/// `case .bike: .blue` ladders, which is how the app ended up with a blue bike and a
/// magenta strength session that matched nothing on the web.
enum SharpitSportTone {
    static func accent(for type: V1ActivityType) -> Color {
        SharpitSportColor.color(token(for: type))
    }

    /// Chip fill — the web's `bg-{hue}-500/20`.
    static func background(for type: V1ActivityType) -> Color {
        accent(for: type).opacity(0.2)
    }

    /// Hairline around a chip — the web's `border-{hue}-500/35`.
    static func border(for type: V1ActivityType) -> Color {
        accent(for: type).opacity(0.35)
    }

    // MARK: - String-keyed entry point

    /// Some payloads carry the sport as free text (`SessionCardModel.sport`) rather than
    /// as a typed enum, so the label is matched before falling back to `.other`.
    static func accent(for sport: String) -> Color {
        accent(for: type(forLabel: sport))
    }

    static func background(for sport: String) -> Color {
        background(for: type(forLabel: sport))
    }

    static func border(for sport: String) -> Color {
        border(for: type(forLabel: sport))
    }

    // MARK: - Mapping

    private static func token(for type: V1ActivityType) -> SharpitRGBA {
        switch type {
        case .run: SharpitSportColor.run
        case .bike: SharpitSportColor.bike
        case .swim: SharpitSportColor.swim
        case .strength: SharpitSportColor.strength
        case .hike: SharpitSportColor.hike
        case .triathlon: SharpitSportColor.triathlon
        case .other: SharpitSportColor.other
        }
    }

    private static func type(forLabel sport: String) -> V1ActivityType {
        let name = sport
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        return switch name {
        case let value where value.contains("course") || value.contains("run"): .run
        case let value where value.contains("velo") || value.contains("cycl") || value.contains("bike"): .bike
        case let value where value.contains("natation") || value.contains("swim"): .swim
        case let value where value.contains("force") || value.contains("muscu") || value.contains("gym"): .strength
        case let value where value.contains("triathlon"): .triathlon
        case let value where value.contains("rando") || value.contains("hike") || value.contains("marche"): .hike
        default: .other
        }
    }
}
