import Foundation

/// An activity's sport. Shared with the widgets, which draw a session's sport the app's way.
nonisolated enum V1ActivityType: String, Codable, Sendable {
    case run = "RUN"
    case bike = "BIKE"
    case swim = "SWIM"
    case strength = "STRENGTH"
    case hike = "HIKE"
    case triathlon = "TRIATHLON"
    case other = "OTHER"

    var label: String {
        switch self {
        case .run: "Course"
        case .bike: "Vélo"
        case .swim: "Natation"
        case .strength: "Force"
        case .hike: "Randonnée"
        case .triathlon: "Triathlon"
        case .other: "Activité"
        }
    }

    var symbolName: String {
        switch self {
        case .run: "figure.run"
        case .bike: "bicycle"
        case .swim: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .hike: "figure.hiking"
        case .triathlon: "figure.mixed.cardio"
        case .other: "figure.mind.and.body"
        }
    }

    /// The sport's identity color, from the web's `SPORT_IDENTITY_HEX` — the one mapping, read
    /// by the app's `SharpitSportTone` and by the widgets.
    var identity: SharpitRGBA {
        switch self {
        case .run: SharpitSportColor.run
        case .bike: SharpitSportColor.bike
        case .swim: SharpitSportColor.swim
        case .strength: SharpitSportColor.strength
        case .hike: SharpitSportColor.hike
        case .triathlon: SharpitSportColor.triathlon
        case .other: SharpitSportColor.other
        }
    }

    /// A sport named in prose (« Course », « Vélo »…), as some payloads carry it.
    init(sportLabel sport: String) {
        let name = sport
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        self = switch name {
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
