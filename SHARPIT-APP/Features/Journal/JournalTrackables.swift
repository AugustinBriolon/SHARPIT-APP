import Foundation

/// The drawer's filter chips, in the web's order.
nonisolated enum JournalCategory: String, CaseIterable, Identifiable, Sendable {
    case automatique
    case bienEtre = "bien_etre"
    case sante
    case medicament
    case nutrition
    case complement
    case sommeil
    case styleVie = "style_vie"
    case comportement

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatique: "Automatique"
        case .sante: "État de santé"
        case .medicament: "Médicament"
        case .nutrition: "Nutrition"
        case .complement: "Complément"
        case .sommeil: "Sommeil"
        case .styleVie: "Style de vie"
        case .comportement: "Comportement"
        case .bienEtre: "Bien-être"
        }
    }
}

/// When a signal happened.
///
/// Its own axis rather than a reading of `JournalCategory`: the category answers "what kind
/// of thing is this" and drives the drawer's filters, the window answers "when did it happen"
/// and drives the screen's order. They happen to coincide today — every Sommeil signal is a
/// night signal — but the web already separates them (`hydration_quality` sits in its sleep
/// group with a day window), so deriving one from the other would break on the next signal
/// the web adds.
nonisolated enum JournalDayWindow: Hashable, Sendable {
    /// The training day itself.
    case calendarDay
    /// The night that ends on this training day: the evening of J-1 through waking on J.
    case priorNight
}

/// One thing the athlete can record on a day.
///
/// `id` is the preferences key and, for every entry here, also the factor key stored on
/// the day. The web's catalogue is larger: its automatic items are filled by device sync,
/// its diet flags and nutrition panel read other endpoints. Those stay out of this list
/// and out of the app's screens, but their preferences survive a save — see `JournalPrefs`.
nonisolated struct JournalTrackable: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A yes / no / unanswered signal stored in the day's factor bag.
        case factor
        case caffeine
        case mood
        case hydration
        /// Derived from the devices, never answered: the athlete turns it on in the drawer
        /// and reads it in the checklist. It carries no state on the day's entry.
        case auto
    }

    let id: String
    let label: String
    let category: JournalCategory
    let symbolName: String
    var kind: Kind = .factor
    var window: JournalDayWindow = .calendarDay
}

nonisolated enum JournalCatalogue {
    static let all: [JournalTrackable] = [
        // Automatique — read from the devices, never answered. Their order is the web's and
        // is the order the checklist renders in, so `JournalAutoItem.ids` has to match.
        JournalTrackable(
            id: "steps_10k",
            label: "Pas (objectif)",
            category: .automatique,
            symbolName: "figure.walk",
            kind: .auto
        ),
        JournalTrackable(
            id: "stress_ok",
            label: "Stress sous cible",
            category: .automatique,
            symbolName: "waveform.path.ecg",
            kind: .auto
        ),
        JournalTrackable(
            id: "nap",
            label: "Sieste",
            category: .automatique,
            symbolName: "moon",
            kind: .auto
        ),
        JournalTrackable(
            id: "cardio_20",
            label: "Cardio",
            category: .automatique,
            symbolName: "heart.fill",
            kind: .auto
        ),
        JournalTrackable(
            id: "strength_20",
            label: "Force",
            category: .automatique,
            symbolName: "dumbbell",
            kind: .auto
        ),
        JournalTrackable(
            id: "sleep_target",
            label: "Sommeil ≥ cible",
            category: .automatique,
            symbolName: "bed.double",
            kind: .auto
        ),
        JournalTrackable(
            id: "body_battery_ok",
            label: "Body Battery",
            category: .automatique,
            symbolName: "battery.75percent",
            kind: .auto
        ),
        JournalTrackable(
            id: "hydration_sync",
            label: "Hydratation (sync)",
            category: .automatique,
            symbolName: "drop.triangle",
            kind: .auto
        ),
        // Shown although nothing feeds it yet: the web lists it too, always as "Données
        // absentes", and hiding it here would make the two clients disagree.
        JournalTrackable(
            id: "outdoor_minutes",
            label: "Temps outdoor",
            category: .automatique,
            symbolName: "sun.max",
            kind: .auto
        ),

        // Bien-être — the three day basics, which are values rather than signals.
        JournalTrackable(
            id: "metric_caffeine",
            label: "Caféine",
            category: .bienEtre,
            symbolName: "cup.and.saucer",
            kind: .caffeine
        ),
        JournalTrackable(
            id: "metric_mood",
            label: "Humeur",
            category: .bienEtre,
            symbolName: "face.smiling",
            kind: .mood
        ),
        JournalTrackable(
            id: "metric_hydration",
            label: "Hydratation",
            category: .bienEtre,
            symbolName: "drop",
            kind: .hydration
        ),

        // État de santé
        JournalTrackable(id: "fever", label: "Fièvre", category: .sante, symbolName: "thermometer.medium"),
        JournalTrackable(id: "menstruation", label: "Menstruation", category: .sante, symbolName: "drop.circle"),
        JournalTrackable(id: "tobacco", label: "Tabac", category: .sante, symbolName: "smoke"),
        JournalTrackable(id: "headache", label: "Maux de tête", category: .sante, symbolName: "brain.head.profile"),
        JournalTrackable(id: "pain", label: "Douleur", category: .sante, symbolName: "bandage"),
        JournalTrackable(id: "allergies", label: "Allergies", category: .sante, symbolName: "wind"),
        JournalTrackable(id: "cold_congestion", label: "Rhume / congestion", category: .sante, symbolName: "humidity"),
        JournalTrackable(id: "cramps", label: "Crampes", category: .sante, symbolName: "bolt"),
        JournalTrackable(
            id: "abdominal_cramps",
            label: "Crampes abdominales",
            category: .sante,
            symbolName: "exclamationmark.circle"
        ),
        JournalTrackable(id: "pregnant", label: "Enceinte", category: .sante, symbolName: "figure.child"),
        JournalTrackable(id: "sexual_activity", label: "Activité sexuelle", category: .sante, symbolName: "heart"),

        // Médicament
        JournalTrackable(id: "medication", label: "Médicament", category: .medicament, symbolName: "pills"),
        JournalTrackable(id: "antibiotic", label: "Antibiotique", category: .medicament, symbolName: "syringe"),
        JournalTrackable(id: "contraception", label: "Contraception", category: .medicament, symbolName: "pill"),
        JournalTrackable(id: "cbd", label: "CBD", category: .medicament, symbolName: "leaf"),

        // Nutrition
        JournalTrackable(id: "added_sugar", label: "Sucre ajouté", category: .nutrition, symbolName: "birthday.cake"),
        JournalTrackable(id: "alcohol", label: "Alcool", category: .nutrition, symbolName: "wineglass"),
        JournalTrackable(id: "meal_out", label: "Repas hors domicile", category: .nutrition, symbolName: "fork.knife"),
        JournalTrackable(
            id: "skipped_meal",
            label: "Repas sauté",
            category: .nutrition,
            symbolName: "fork.knife.circle"
        ),

        // Compléments
        JournalTrackable(id: "omega3", label: "Oméga-3", category: .complement, symbolName: "pill"),
        JournalTrackable(id: "creatine", label: "Créatine", category: .complement, symbolName: "pill"),
        JournalTrackable(id: "vitamin_d", label: "Vitamine D", category: .complement, symbolName: "pill"),
        JournalTrackable(id: "magnesium", label: "Magnésium", category: .complement, symbolName: "pill"),
        JournalTrackable(id: "ashwagandha", label: "Ashwagandha", category: .complement, symbolName: "pill"),
        JournalTrackable(id: "multivitamin", label: "Multivitamines", category: .complement, symbolName: "pills"),
        JournalTrackable(id: "zinc", label: "Zinc", category: .complement, symbolName: "pill"),
        JournalTrackable(id: "probiotic", label: "Probiotique", category: .complement, symbolName: "pill"),
        JournalTrackable(id: "electrolytes", label: "Électrolytes", category: .complement, symbolName: "drop"),
        JournalTrackable(id: "collagen", label: "Collagène", category: .complement, symbolName: "pill"),
        JournalTrackable(
            id: "protein_powder",
            label: "Protéine en poudre",
            category: .complement,
            symbolName: "pills"
        ),
        JournalTrackable(
            id: "hydration_quality",
            label: "Bonne hydratation (ressenti)",
            category: .complement,
            symbolName: "drop.fill"
        ),

        // Sommeil — the seven the web files in the prior-night window. They describe the
        // night that ends this morning, so the screen groups them apart from the day.
        JournalTrackable(
            id: "late_meal",
            label: "Repas tardif",
            category: .sommeil,
            symbolName: "fork.knife.circle",
            window: .priorNight
        ),
        JournalTrackable(
            id: "device_in_bed",
            label: "Écran au lit",
            category: .sommeil,
            symbolName: "iphone",
            window: .priorNight
        ),
        JournalTrackable(
            id: "shared_bed",
            label: "Lit partagé",
            category: .sommeil,
            symbolName: "person.2",
            window: .priorNight
        ),
        JournalTrackable(
            id: "earplugs",
            label: "Bouchons d'oreille",
            category: .sommeil,
            symbolName: "ear",
            window: .priorNight
        ),
        JournalTrackable(
            id: "sleep_mask",
            label: "Masque de sommeil",
            category: .sommeil,
            symbolName: "eye.slash",
            window: .priorNight
        ),
        JournalTrackable(
            id: "pet_in_room",
            label: "Animal dans la chambre",
            category: .sommeil,
            symbolName: "pawprint",
            window: .priorNight
        ),
        JournalTrackable(
            id: "melatonin",
            label: "Mélatonine",
            category: .sommeil,
            symbolName: "moon.zzz",
            window: .priorNight
        ),

        // Style de vie
        JournalTrackable(
            id: "intermittent_fasting",
            label: "Jeûne intermittent",
            category: .styleVie,
            symbolName: "alarm"
        ),
        JournalTrackable(id: "sun_exposure", label: "Exposition au soleil", category: .styleVie, symbolName: "sun.max"),
        JournalTrackable(id: "massage", label: "Massage", category: .styleVie, symbolName: "hand.raised"),
        JournalTrackable(
            id: "mobility",
            label: "Étirements / mobilité",
            category: .styleVie,
            symbolName: "figure.flexibility"
        ),
        JournalTrackable(id: "meditation", label: "Méditation", category: .styleVie, symbolName: "brain.head.profile"),
        JournalTrackable(id: "easy_walk", label: "Marche légère", category: .styleVie, symbolName: "figure.walk"),
        JournalTrackable(
            id: "pneumatic_recovery",
            label: "Récupération pneumatique",
            category: .styleVie,
            symbolName: "waveform.path"
        ),

        // Comportement
        JournalTrackable(id: "night_work", label: "Travail de nuit", category: .comportement, symbolName: "moon.stars"),

        // Bien-être — recovery practices
        JournalTrackable(id: "sauna", label: "Sauna", category: .bienEtre, symbolName: "flame"),
        JournalTrackable(id: "cold_shower", label: "Douche froide", category: .bienEtre, symbolName: "snowflake"),
        JournalTrackable(id: "ice_bath", label: "Bain de glace", category: .bienEtre, symbolName: "snowflake.circle"),
        JournalTrackable(id: "cupping", label: "Cupping", category: .bienEtre, symbolName: "circle.grid.2x2"),
        JournalTrackable(id: "chiropractor", label: "Chiropracteur", category: .bienEtre, symbolName: "stethoscope"),
        JournalTrackable(id: "yoga", label: "Yoga", category: .bienEtre, symbolName: "figure.yoga")
    ]

    private static let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func trackable(id: String) -> JournalTrackable? {
        byId[id]
    }

    static func inCategory(_ category: JournalCategory) -> [JournalTrackable] {
        all.filter { $0.category == category }
    }

    static func inWindow(_ window: JournalDayWindow) -> [JournalTrackable] {
        all.filter { $0.window == window }
    }

    static let customSymbolName = "sparkles"
}
