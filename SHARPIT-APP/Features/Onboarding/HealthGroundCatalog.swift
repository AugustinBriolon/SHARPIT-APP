import Foundation

/// The health grounds the body step offers, mirroring the web catalog
/// (`@sharpit/app/lib/health-grounds/catalog`, SHARPIT ADR-124): keys and stage ids must match it,
/// since the server refuses a stage that is not the key's own. The rules each stage brings live
/// on the server only.
nonisolated enum HealthGroundCatalog {
    struct Stage: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
    }

    struct Entry: Identifiable, Hashable, Sendable {
        let key: String
        let label: String
        let question: String
        let symbolName: String
        let stages: [Stage]
        /// Offered to a woman only.
        var womenOnly = false
        /// Asks for a few words (« Autre »).
        var asksDetails = false

        var id: String { key }

        func stage(_ id: String) -> Stage? { stages.first { $0.id == id } }
    }

    static let all: [Entry] = [
        Entry(
            key: "osteoporosis", label: String(localized: "Ostéoporose / ostéopénie"),
            question: String(localized: "Où en es-tu ?"), symbolName: "figure.stand",
            stages: [
                Stage(id: "osteopenia", label: String(localized: "Ostéopénie (densité basse)")),
                Stage(id: "osteoporosis", label: String(localized: "Ostéoporose diagnostiquée")),
                Stage(id: "vertebral_fracture", label: String(localized: "Avec fracture vertébrale")),
            ]
        ),
        Entry(
            key: "menstrual_cycle", label: String(localized: "Cycle menstruel"),
            question: String(localized: "Comment est ton cycle ?"), symbolName: "circle.dotted",
            stages: [
                Stage(id: "regular", label: String(localized: "Régulier, sans gêne")),
                Stage(id: "regular_symptoms", label: String(localized: "Régulier, avec symptômes")),
                Stage(id: "irregular", label: String(localized: "Irrégulier ou absent")),
            ],
            womenOnly: true
        ),
        Entry(
            key: "pregnancy", label: String(localized: "Grossesse"),
            question: String(localized: "À quel trimestre ?"), symbolName: "figure.2.and.child.holdinghands",
            stages: [
                Stage(id: "t1", label: String(localized: "1er trimestre")),
                Stage(id: "t2", label: String(localized: "2e trimestre")),
                Stage(id: "t3", label: String(localized: "3e trimestre")),
            ],
            womenOnly: true
        ),
        Entry(
            key: "postpartum", label: String(localized: "Post-partum"),
            question: String(localized: "Depuis l'accouchement ?"), symbolName: "stroller",
            stages: [
                Stage(id: "under_6_weeks", label: String(localized: "Moins de 6 semaines")),
                Stage(id: "6_to_12_weeks", label: String(localized: "6 à 12 semaines")),
                Stage(id: "over_12_weeks", label: String(localized: "Plus de 12 semaines")),
            ],
            womenOnly: true
        ),
        Entry(
            key: "diabetes", label: String(localized: "Diabète"),
            question: String(localized: "Où en es-tu ?"), symbolName: "drop",
            stages: [
                Stage(id: "type1_stable", label: String(localized: "Type 1, équilibré")),
                Stage(id: "type2_stable", label: String(localized: "Type 2, équilibré")),
                Stage(id: "recent_hypos", label: String(localized: "Hypoglycémies récentes ou équilibre instable")),
            ]
        ),
        Entry(
            key: "asthma", label: String(localized: "Asthme"),
            question: String(localized: "Ton asthme est-il contrôlé ?"), symbolName: "lungs",
            stages: [
                Stage(id: "controlled", label: String(localized: "Contrôlé")),
                Stage(id: "uncontrolled", label: String(localized: "Pas bien contrôlé")),
            ]
        ),
        Entry(
            key: "cardiovascular", label: String(localized: "Tension ou cœur"),
            question: String(localized: "Où en es-tu ?"), symbolName: "heart",
            stages: [
                Stage(id: "cleared", label: String(localized: "Suivi et feu vert du médecin")),
                Stage(id: "not_cleared", label: String(localized: "Pas encore d'avis médical")),
            ]
        ),
        Entry(
            key: "osteoarthritis", label: String(localized: "Arthrose"),
            question: String(localized: "Quelle gêne au quotidien ?"), symbolName: "figure.walk",
            stages: [
                Stage(id: "mild", label: String(localized: "Légère")),
                Stage(id: "moderate", label: String(localized: "Modérée")),
                Stage(id: "severe", label: String(localized: "Forte")),
            ]
        ),
        Entry(
            key: "other", label: String(localized: "Autre"),
            question: String(localized: "Précise en quelques mots"), symbolName: "ellipsis",
            stages: [Stage(id: "declared", label: String(localized: "Déclaré"))],
            asksDetails: true
        ),
    ]

    static func entries(for sex: AthleteSex?) -> [Entry] {
        all.filter { !$0.womenOnly || sex == .female }
    }

    static func entry(_ key: String) -> Entry? { all.first { $0.key == key } }

    /// Whether a stage owes a medical go-ahead before vigorous work — mirrors `needsClearance`.
    static let clearanceStages: Set<String> = [
        "osteoporosis.vertebral_fracture", "pregnancy.t1", "pregnancy.t2", "pregnancy.t3",
        "postpartum.under_6_weeks", "postpartum.6_to_12_weeks", "menstrual_cycle.irregular",
        "diabetes.recent_hypos", "asthma.uncontrolled", "cardiovascular.not_cleared", "osteoarthritis.severe",
    ]

    static func needsClearance(_ ground: HealthGroundInput) -> Bool {
        clearanceStages.contains("\(ground.key).\(ground.stage)")
    }
}
