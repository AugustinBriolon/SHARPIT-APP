import Foundation

/// What « Ajuster le planning » is told when the athlete taps Résumé's conflict card: the trip,
/// its days and what training becomes, as « Rattraper ma semaine » says a miss (`docs/adr/0029`).
enum PlanTripAdaptation {
    static func focus(for conflict: V1TodayTravelConflict) -> String {
        let when = TravelConflictReadout.days(conflict)
        let what = conflict.type == .constraint
            ? String(localized: "J'ai une contrainte « \(conflict.name) » \(when)")
            : String(localized: "Je suis en déplacement à \(conflict.name) \(when)")
        let training = switch conflict.trainingConstraint {
        case .none: String(localized: "pas d'entraînement possible.")
        case .reduced: String(localized: "charge et intensité réduites.")
        case .mobilityOnly: String(localized: "mobilité seulement.")
        case .full: String(localized: "seuls certains sports sont possibles.")
        }
        return "\(what) : \(training) "
            + String(localized: "Adapte les séances concernées et la suite si besoin, en gardant les séances clés.")
    }
}
