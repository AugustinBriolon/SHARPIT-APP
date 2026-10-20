import Foundation

/// Capability inventory for session generation (home trainer, fins, gym membership…).
/// Mirrors `src/lib/equipment/catalog.ts` on the web.
nonisolated struct V1AthleteEquipment: Codable, Sendable, Equatable {
    var version: Int = 1
    var strengthVenue: String?
    var owned: [String] = []

    enum StrengthVenue: String, CaseIterable, Identifiable, Codable, Sendable {
        case gym
        case home
        case both
        case bodyweight

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gym: String(localized: "Salle")
            case .home: String(localized: "Maison")
            case .both: String(localized: "Salle + maison")
            case .bodyweight: String(localized: "Poids du corps")
            }
        }

        var symbolName: String {
            switch self {
            case .gym: "dumbbell"
            case .home: "house"
            case .both: "arrow.triangle.2.circlepath"
            case .bodyweight: "figure.cross.training"
            }
        }

        var description: String {
            switch self {
            case .gym: String(localized: "Inscription en salle — machines, racks et câbles.")
            case .home: String(localized: "Matériel à domicile uniquement.")
            case .both: String(localized: "Salle + matériel à la maison.")
            case .bodyweight: String(localized: "Séances au poids du corps uniquement.")
            }
        }

        /// Chips the athlete toggles (no exclusive « Les deux » — both flags → `.both` on the wire).
        enum Toggle: String, CaseIterable, Identifiable, Sendable {
            case gym
            case home
            case bodyweight

            var id: String { rawValue }

            var title: String {
                switch self {
                case .gym: String(localized: "Salle")
                case .home: String(localized: "Maison")
                case .bodyweight: String(localized: "Poids du corps")
                }
            }

            var symbolName: String {
                switch self {
                case .gym: "dumbbell"
                case .home: "house"
                case .bodyweight: "figure.cross.training"
                }
            }
        }

        /// Wire value from the multi-select chips.
        static func from(toggles: Set<Toggle>) -> StrengthVenue {
            if toggles.contains(.bodyweight) { return .bodyweight }
            let gym = toggles.contains(.gym)
            let home = toggles.contains(.home)
            switch (gym, home) {
            case (true, true): return .both
            case (true, false): return .gym
            case (false, true): return .home
            case (false, false): return .bodyweight
            }
        }

        /// Chips that represent this wire value.
        var toggles: Set<Toggle> {
            switch self {
            case .gym: [.gym]
            case .home: [.home]
            case .both: [.gym, .home]
            case .bodyweight: [.bodyweight]
            }
        }

        /// Toggle one chip: bodyweight clears salle/maison; salle/maison clear bodyweight.
        static func toggling(_ chip: Toggle, in current: StrengthVenue) -> StrengthVenue {
            var selected = current.toggles
            if selected.contains(chip) {
                selected.remove(chip)
            } else if chip == .bodyweight {
                selected = [.bodyweight]
            } else {
                selected.remove(.bodyweight)
                selected.insert(chip)
            }
            return from(toggles: selected)
        }
    }
}

nonisolated enum EquipmentSport: String, CaseIterable, Identifiable, Sendable {
    case run = "RUN"
    case bike = "BIKE"
    case swim = "SWIM"
    case strength = "STRENGTH"
    case mobility = "MOBILITY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: String(localized: "Course")
        case .bike: String(localized: "Vélo")
        case .swim: String(localized: "Natation")
        case .strength: String(localized: "Musculation")
        case .mobility: String(localized: "Mobilité")
        }
    }

    var symbolName: String {
        switch self {
        case .run: "figure.run"
        case .bike: "bicycle"
        case .swim: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .mobility: "figure.yoga"
        }
    }
}

nonisolated struct EquipmentCatalogItem: Identifiable, Sendable, Equatable {
    let id: String
    let sport: EquipmentSport
    let label: String
    let impact: String
    let symbolName: String
    var requiresHomeStrength: Bool = false
}

nonisolated enum EquipmentCatalog {
    static let all: [EquipmentCatalogItem] = [
        // Course
        EquipmentCatalogItem(
            id: "run_treadmill",
            sport: .run,
            label: String(localized: "Tapis de course"),
            impact: String(localized: "Séances indoor structurées par mauvais temps ou le soir."),
            symbolName: "figure.walk"
        ),
        EquipmentCatalogItem(
            id: "run_track",
            sport: .run,
            label: String(localized: "Accès piste"),
            impact: String(localized: "Fractions chronométrées et travail de vitesse précis."),
            symbolName: "stopwatch"
        ),
        EquipmentCatalogItem(
            id: "run_trail",
            sport: .run,
            label: String(localized: "Trail possible"),
            impact: String(localized: "Séances dénivelé et terrain technique."),
            symbolName: "mountain.2"
        ),

        // Vélo
        EquipmentCatalogItem(
            id: "bike_home_trainer",
            sport: .bike,
            label: String(localized: "Home trainer"),
            impact: String(localized: "Séances indoor structurées (pluie, soir, plan B météo)."),
            symbolName: "figure.indoor.cycle"
        ),
        EquipmentCatalogItem(
            id: "bike_power_meter",
            sport: .bike,
            label: String(localized: "Capteur de puissance"),
            impact: String(localized: "Prescriptions précises en watts."),
            symbolName: "bolt"
        ),
        EquipmentCatalogItem(
            id: "bike_outdoor",
            sport: .bike,
            label: String(localized: "Vélo outdoor"),
            impact: String(localized: "Sorties route ou endurance longue dehors."),
            symbolName: "bicycle"
        ),

        // Natation
        EquipmentCatalogItem(
            id: "swim_pool",
            sport: .swim,
            label: String(localized: "Accès piscine"),
            impact: String(localized: "Séances natation structurées."),
            symbolName: "figure.pool.swim"
        ),
        EquipmentCatalogItem(
            id: "swim_fins",
            sport: .swim,
            label: String(localized: "Palmes"),
            impact: String(localized: "Travail technique jambes et endurance spécifique."),
            symbolName: "water.waves.and.arrow.down"
        ),
        EquipmentCatalogItem(
            id: "swim_paddles",
            sport: .swim,
            label: String(localized: "Plaquettes"),
            impact: String(localized: "Renforcement bras et technique de traction."),
            symbolName: "hand.raised.square"
        ),
        EquipmentCatalogItem(
            id: "swim_pull_buoy",
            sport: .swim,
            label: String(localized: "Pull buoy"),
            impact: String(localized: "Focus haut du corps sans battements."),
            symbolName: "capsule.portrait.fill"
        ),

        // Musculation
        EquipmentCatalogItem(
            id: "strength_dumbbells",
            sport: .strength,
            label: String(localized: "Haltères / kettlebell"),
            impact: String(localized: "Charge libre à domicile pour le renfo."),
            symbolName: "",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_barbell",
            sport: .strength,
            label: String(localized: "Barre + disques"),
            impact: String(localized: "Mouvements composés chargés à domicile."),
            symbolName: "",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_bench",
            sport: .strength,
            label: String(localized: "Banc"),
            impact: String(localized: "Développés et variations allongées."),
            symbolName: "",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_pullup_bar",
            sport: .strength,
            label: String(localized: "Barre de traction"),
            impact: String(localized: "Tractions et gainage vertical."),
            symbolName: "",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_bands",
            sport: .strength,
            label: String(localized: "Élastiques"),
            impact: String(localized: "Activation, assistance et charge progressive."),
            symbolName: "",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_trx",
            sport: .strength,
            label: "TRX / sangles",
            impact: String(localized: "Renfo en suspension au poids du corps."),
            symbolName: "",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_rings",
            sport: .strength,
            label: String(localized: "Anneaux de gymnastique"),
            impact: String(localized: "Tirage et poussée instables."),
            symbolName: "",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_dip_bars",
            sport: .strength,
            label: String(localized: "Barres de dips"),
            impact: String(localized: "Poussée verticale lestable."),
            symbolName: "",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_weighted_vest",
            sport: .strength,
            label: String(localized: "Gilet lesté"),
            impact: String(localized: "Lest portable (tractions, pompes, côtes)."),
            symbolName: ""
        ),

        // Mobilité
        EquipmentCatalogItem(
            id: "mobility_foam_roller",
            sport: .mobility,
            label: "Foam roller / stick",
            impact: String(localized: "Récupération et mobilité ciblée."),
            symbolName: "cylinder"
        ),
        EquipmentCatalogItem(
            id: "mobility_bands",
            sport: .mobility,
            label: String(localized: "Élastiques mobilité"),
            impact: String(localized: "Épaules, hanches et activation douce."),
            symbolName: "lines.measurement.horizontal"
        ),
        EquipmentCatalogItem(
            id: "mobility_tennis_ball",
            sport: .mobility,
            label: String(localized: "Balle de massage"),
            impact: String(localized: "Points gâchettes, pieds, fessiers."),
            symbolName: "circle.fill"
        ),
        EquipmentCatalogItem(
            id: "mobility_yoga_block",
            sport: .mobility,
            label: String(localized: "Brique de yoga"),
            impact: String(localized: "Amplitude assistée et étirements soutenus."),
            symbolName: "square"
        ),
    ]

    static func items(for sport: EquipmentSport, venue: V1AthleteEquipment.StrengthVenue?) -> [EquipmentCatalogItem] {
        all.filter { item in
            guard item.sport == sport else { return false }
            if item.requiresHomeStrength {
                return venue == .home || venue == .both
            }
            return true
        }
    }
}
