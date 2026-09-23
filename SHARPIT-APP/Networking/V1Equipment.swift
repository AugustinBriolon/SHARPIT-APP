import Foundation

/// Capability inventory for session generation (home trainer, fins, gym membership…).
/// Mirrors `src/lib/equipment/catalog.ts` on the web.
nonisolated struct V1AthleteEquipment: Codable, Sendable, Equatable {
    var version: Int = 1
    var strengthVenue: String?
    var owned: [String] = []

    enum StrengthVenue: String, CaseIterable, Identifiable, Sendable {
        case gym
        case home
        case both
        case bodyweight

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gym: "Salle"
            case .home: "Maison"
            case .both: "Les deux"
            case .bodyweight: "Poids du corps"
            }
        }

        var description: String {
            switch self {
            case .gym: "Inscription en salle — machines, racks et câbles."
            case .home: "Matériel à domicile uniquement."
            case .both: "Salle + matériel à la maison."
            case .bodyweight: "Séances au poids du corps uniquement."
            }
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
        case .run: "Course"
        case .bike: "Vélo"
        case .swim: "Natation"
        case .strength: "Musculation"
        case .mobility: "Mobilité"
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
            label: "Tapis de course",
            impact: "Séances indoor structurées par mauvais temps ou le soir.",
            symbolName: "figure.walk"
        ),
        EquipmentCatalogItem(
            id: "run_track",
            sport: .run,
            label: "Accès piste",
            impact: "Fractions chronométrées et travail de vitesse précis.",
            symbolName: "stopwatch"
        ),
        EquipmentCatalogItem(
            id: "run_trail",
            sport: .run,
            label: "Trail possible",
            impact: "Séances dénivelé et terrain technique.",
            symbolName: "mountain.2"
        ),

        // Vélo
        EquipmentCatalogItem(
            id: "bike_home_trainer",
            sport: .bike,
            label: "Home trainer",
            impact: "Séances indoor structurées (pluie, soir, plan B météo).",
            symbolName: "figure.indoor.cycle"
        ),
        EquipmentCatalogItem(
            id: "bike_power_meter",
            sport: .bike,
            label: "Capteur de puissance",
            impact: "Prescriptions précises en watts.",
            symbolName: "bolt"
        ),
        EquipmentCatalogItem(
            id: "bike_outdoor",
            sport: .bike,
            label: "Vélo outdoor",
            impact: "Sorties route ou endurance longue dehors.",
            symbolName: "bicycle"
        ),

        // Natation
        EquipmentCatalogItem(
            id: "swim_pool",
            sport: .swim,
            label: "Accès piscine",
            impact: "Séances natation structurées.",
            symbolName: "figure.pool.swim"
        ),
        EquipmentCatalogItem(
            id: "swim_fins",
            sport: .swim,
            label: "Palmes",
            impact: "Travail technique jambes et endurance spécifique.",
            symbolName: "water.waves.and.arrow.down"
        ),
        EquipmentCatalogItem(
            id: "swim_paddles",
            sport: .swim,
            label: "Plaquettes",
            impact: "Renforcement bras et technique de traction.",
            symbolName: "hand.raised.square"
        ),
        EquipmentCatalogItem(
            id: "swim_pull_buoy",
            sport: .swim,
            label: "Pull buoy",
            impact: "Focus haut du corps sans battements.",
            symbolName: "capsule.portrait.fill"
        ),

        // Musculation
        EquipmentCatalogItem(
            id: "strength_dumbbells",
            sport: .strength,
            label: "Haltères / kettlebell",
            impact: "Charge libre à domicile pour le renfo.",
            symbolName: "dumbbell",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_barbell",
            sport: .strength,
            label: "Barre + disques",
            impact: "Mouvements composés chargés à domicile.",
            symbolName: "circle.circle",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_bench",
            sport: .strength,
            label: "Banc",
            impact: "Développés et variations allongées.",
            symbolName: "table.furniture.fill",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_pullup_bar",
            sport: .strength,
            label: "Barre de traction",
            impact: "Tractions et gainage vertical.",
            symbolName: "figure.strengthtraining.traditional",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_bands",
            sport: .strength,
            label: "Élastiques",
            impact: "Activation, assistance et charge progressive.",
            symbolName: "lines.measurement.horizontal",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_trx",
            sport: .strength,
            label: "TRX / sangles",
            impact: "Renfo en suspension au poids du corps.",
            symbolName: "figure.gymnastics",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_rings",
            sport: .strength,
            label: "Anneaux de gymnastique",
            impact: "Tirage et poussée instables.",
            symbolName: "circle",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_dip_bars",
            sport: .strength,
            label: "Barres de dips",
            impact: "Poussée verticale lestable.",
            symbolName: "pause",
            requiresHomeStrength: true
        ),
        EquipmentCatalogItem(
            id: "strength_weighted_vest",
            sport: .strength,
            label: "Gilet lesté",
            impact: "Lest portable (tractions, pompes, côtes).",
            symbolName: "tshirt"
        ),

        // Mobilité
        EquipmentCatalogItem(
            id: "mobility_foam_roller",
            sport: .mobility,
            label: "Foam roller / stick",
            impact: "Récupération et mobilité ciblée.",
            symbolName: "cylinder"
        ),
        EquipmentCatalogItem(
            id: "mobility_bands",
            sport: .mobility,
            label: "Élastiques mobilité",
            impact: "Épaules, hanches et activation douce.",
            symbolName: "lines.measurement.horizontal"
        ),
        EquipmentCatalogItem(
            id: "mobility_tennis_ball",
            sport: .mobility,
            label: "Balle de massage",
            impact: "Points gâchettes, pieds, fessiers.",
            symbolName: "circle.fill"
        ),
        EquipmentCatalogItem(
            id: "mobility_yoga_block",
            sport: .mobility,
            label: "Brique de yoga",
            impact: "Amplitude assistée et étirements soutenus.",
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
