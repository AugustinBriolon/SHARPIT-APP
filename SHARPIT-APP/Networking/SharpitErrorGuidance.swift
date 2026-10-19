import Foundation

/// What to tell the athlete when a read fails: the cause in their words and what to do about
/// it — never only that something went wrong.
nonisolated enum SharpitErrorGuidance {
    static func message(for error: Error, subject: String) -> String {
        switch error as? SharpitAPIError {
        case .transport?:
            String(localized: "Pas de connexion internet. Vérifie ton réseau, puis réessaie.")
        case .rateLimited?:
            String(localized: "Trop de demandes d'affilée. Réessaie dans une minute.")
        case .unauthorized?:
            String(localized: "Ta session a expiré. Reconnecte-toi depuis Paramètres › Compte.")
        case .googleNeedsReconnect(let text):
            text
        default:
            String(localized: "\(subject) n'a pas pu être chargé. Le serveur n'a pas répondu, réessaie dans un instant.")
        }
    }
}
