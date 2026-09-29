import Foundation

/// The parts of SharpIt the athlete uses — the web's `FeaturePrefs` v1, on the profile. A
/// feature turned off disappears everywhere it shows (its page, its Résumé card, its widget);
/// its data is kept. Shared with the widgets, which draw a switched-off feature as such.
nonisolated struct V1FeaturePrefs: Codable, Sendable, Equatable {
    var journal = true
    var nutrition = true
    /// Corps: the body readout and the weight.
    var health = true
    var regularity = true

    init(journal: Bool = true, nutrition: Bool = true, health: Bool = true, regularity: Bool = true) {
        self.journal = journal
        self.nutrition = nutrition
        self.health = health
        self.regularity = regularity
    }

    /// A key missing from the payload is on, as the server resolves it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        journal = (try? container.decodeIfPresent(Bool.self, forKey: .journal)) ?? true
        nutrition = (try? container.decodeIfPresent(Bool.self, forKey: .nutrition)) ?? true
        health = (try? container.decodeIfPresent(Bool.self, forKey: .health)) ?? true
        regularity = (try? container.decodeIfPresent(Bool.self, forKey: .regularity)) ?? true
    }

    enum CodingKeys: String, CodingKey { case journal, nutrition, health, regularity }
}

/// One feature the athlete can turn off, with the words Paramètres uses for it.
nonisolated enum SharpitFeature: String, CaseIterable, Identifiable, Sendable {
    case journal, nutrition, health, regularity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journal: "Journal"
        case .nutrition: "Nutrition"
        case .health: "Corps"
        case .regularity: "Régularité"
        }
    }

    /// What disappears when it is off, said exactly.
    var detail: String {
        switch self {
        case .journal: "Le bouton Journal de Résumé et la page du journal."
        case .nutrition: "La carte Nutrition de Résumé, la page Nutrition et le widget Nutrition."
        case .health: "L'onglet Corps et le widget Poids."
        case .regularity: "La carte Régularité de Résumé et le widget Régularité."
        }
    }

    var symbolName: String {
        switch self {
        case .journal: "book.closed"
        case .nutrition: "fork.knife"
        case .health: "figure.stand"
        case .regularity: "calendar"
        }
    }
}

nonisolated extension V1FeaturePrefs {
    func isOn(_ feature: SharpitFeature) -> Bool {
        switch feature {
        case .journal: journal
        case .nutrition: nutrition
        case .health: health
        case .regularity: regularity
        }
    }

    mutating func set(_ feature: SharpitFeature, _ on: Bool) {
        switch feature {
        case .journal: journal = on
        case .nutrition: nutrition = on
        case .health: health = on
        case .regularity: regularity = on
        }
    }
}
