import Foundation

/// Every data source Paramètres › Sources de données lists, whatever links it: the two the
/// iPhone owns (Apple Health, Apple Calendar) and the four it hands to an in-app OAuth flow.
/// One type so the connected list, the manage sheet and the « + » sheet speak about a source
/// the same way (`docs/adr/0014`).
nonisolated enum ManagedSource: String, CaseIterable, Identifiable, Sendable {
    case appleHealth
    case appleCalendar
    case withings
    case google
    case strava
    case garmin

    var id: String { rawValue }

    /// The OAuth twin, for the sources the server links and revokes.
    var oauth: DisconnectableSource? {
        switch self {
        case .appleHealth, .appleCalendar: nil
        case .withings: .withings
        case .google: .google
        case .strava: .strava
        case .garmin: .garmin
        }
    }

    var name: String {
        switch self {
        case .appleHealth: String(localized: "Apple Santé")
        case .appleCalendar: String(localized: "Calendrier Apple")
        case .withings, .google, .strava, .garmin: oauth?.name ?? rawValue
        }
    }

    var logo: ProviderLogo.Provider {
        switch self {
        case .appleHealth: .appleHealth
        case .appleCalendar: .appleCalendar
        case .withings: .withings
        case .google: .google
        case .strava: .strava
        case .garmin: .garmin
        }
    }

    /// What the source brings, once linked.
    var purpose: String {
        switch self {
        case .appleHealth: String(localized: "Séances, sommeil et cœur de ta montre")
        case .appleCalendar: String(localized: "Séances planifiées et créneaux occupés")
        case .withings, .google, .strava, .garmin: oauth?.purpose ?? ""
        }
    }

    /// Why linking it is worth it, in what the coach does with it.
    var benefit: String {
        switch self {
        case .appleHealth:
            String(localized: "Le coach lit tes séances, ton sommeil et ton cœur au repos pour mesurer ta récupération et ajuster ton plan, sans rien saisir.")
        case .appleCalendar:
            String(localized: "Tes séances apparaissent dans ton agenda et le coach évite tes créneaux déjà pris en construisant ta semaine.")
        case .withings:
            String(localized: "Ta balance envoie poids et composition corporelle : le coach suit ta tendance plutôt qu'une pesée isolée.")
        case .google:
            String(localized: "Le coach voit tes créneaux libres dans Google Agenda et place tes séances quand tu es disponible.")
        case .strava:
            String(localized: "Tes sorties Strava rejoignent ton historique : le coach compte toute ta charge, même hors montre.")
        case .garmin:
            String(localized: "Tes séances, ton sommeil et ta VFC Garmin arrivent seuls : le coach lit ta récupération sans rien saisir.")
        }
    }

    var disconnectTitle: String { String(localized: "Déconnecter \(name) ?") }

    var disconnectLabel: String { String(localized: "Déconnecter \(name)") }

    /// What stops, then what stays — the athlete decides on facts, never on a warning tone.
    var disconnectMessage: String {
        switch self {
        case .appleHealth:
            String(localized: "SharpIt ne lira plus tes séances, ton sommeil ni ton cœur depuis Santé. Ce qui est déjà importé est conservé.")
        case .appleCalendar:
            String(localized: "Tes séances ne seront plus copiées dans le calendrier de ton iPhone et le coach ne lira plus tes créneaux occupés.")
        case .withings, .google, .strava, .garmin:
            oauth?.confirmationMessage ?? ""
        }
    }
}
