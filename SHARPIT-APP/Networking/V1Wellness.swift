import Foundation

/// The 1–5 tiles every morning-wellness dimension is picked on.
nonisolated enum WellnessScore: Int, CaseIterable, Identifiable, Sendable {
    case one = 1
    case two
    case three
    case four
    case five

    var id: Int { rawValue }
}

/// One morning check-in, in the shape `/api/wellness-checkin` stores it.
///
/// Soreness is the odd one out: the athlete picks it on the same 1–5 tiles, but the
/// recovery extractors read a frozen 0–10 domain scale, so it is mapped on the way in
/// and back on the way out.
nonisolated struct V1WellnessEntry: Codable, Equatable, Sendable {
    var mood: Int
    var energyLevel: Int
    var perceivedSoreness: Int
    var stressLevel: Int
    var notes: String?
}

nonisolated struct V1WellnessCheckin: Decodable, Equatable, Sendable {
    let completed: Bool
    let entry: V1WellnessEntry?
}

nonisolated enum WellnessSoreness {
    /// 1 → 0 … 5 → 10, linear, matching `mapSorenessUiToDomain` on the web.
    static func domain(fromUI score: WellnessScore) -> Int {
        Int((Double(score.rawValue - 1) * 10 / 4).rounded())
    }

    /// Clamps to 0–10 then snaps back onto the 1–5 tiles.
    static func ui(fromDomain score: Int) -> WellnessScore {
        let clamped = min(max(score, 0), 10)
        let snapped = Int((Double(clamped) * 4 / 10 + 1).rounded())
        return WellnessScore(rawValue: min(max(snapped, 1), 5)) ?? .three
    }
}

/// The dimensions of the check-in, in the order the web asks them.
nonisolated enum WellnessDimension: String, CaseIterable, Identifiable, Sendable {
    case mood
    case energy
    case soreness
    case stress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mood: "Humeur"
        case .energy: "Énergie"
        case .soreness: "Corps"
        case .stress: "Stress"
        }
    }

    var hint: String {
        switch self {
        case .mood: "Comment te sens-tu psychologiquement ?"
        case .energy: "Ton niveau d'énergie au réveil."
        case .soreness: "Sensations musculaires et courbatures."
        case .stress: "Charge mentale, tension ou pression ressentie."
        }
    }

    func label(for score: WellnessScore) -> String {
        Self.labels(for: self)[score.rawValue - 1]
    }

    private static func labels(for dimension: WellnessDimension) -> [String] {
        switch dimension {
        case .mood: ["Très bas", "Bas", "Correct", "Bien", "Top"]
        case .energy: ["Épuisé", "Fatigué", "Moyen", "En forme", "Plein"]
        case .soreness: ["Aucune", "Légère", "Modérée", "Forte", "Max"]
        case .stress: ["Calme", "Léger", "Modéré", "Élevé", "Très haut"]
        }
    }
}
