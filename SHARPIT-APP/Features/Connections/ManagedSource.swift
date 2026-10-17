import Foundation

/// Every data source Paramètres › Sources de données lists, whatever links it: the two the
/// iPhone owns (Apple Health, Apple Calendar) and the three it hands to an in-app OAuth flow.
/// One type so the connected list, the manage sheet and the « + » sheet speak about a source
/// the same way (`docs/adr/0014`).
nonisolated enum ManagedSource: String, CaseIterable, Identifiable, Sendable {
    case appleHealth
    case appleCalendar
    case withings
    case google
    case strava

    var id: String { rawValue }

    /// The OAuth twin, for the sources the server links and revokes.
    var oauth: DisconnectableSource? {
        switch self {
        case .appleHealth, .appleCalendar: nil
        case .withings: .withings
        case .google: .google
        case .strava: .strava
        }
    }

    var name: String {
        switch self {
        case .appleHealth: "Apple Santé"
        case .appleCalendar: "Calendrier Apple"
        case .withings, .google, .strava: oauth?.name ?? rawValue
        }
    }

    var logo: ProviderLogo.Provider {
        switch self {
        case .appleHealth: .appleHealth
        case .appleCalendar: .appleCalendar
        case .withings: .withings
        case .google: .google
        case .strava: .strava
        }
    }

    /// What the source brings, once linked.
    var purpose: String {
        switch self {
        case .appleHealth: "Séances, sommeil et cœur de ta montre"
        case .appleCalendar: "Séances planifiées et créneaux occupés"
        case .withings, .google, .strava: oauth?.purpose ?? ""
        }
    }

    var disconnectTitle: String { "Déconnecter \(name) ?" }

    var disconnectLabel: String { "Déconnecter \(name)" }

    /// What stops, then what stays — the athlete decides on facts, never on a warning tone.
    var disconnectMessage: String {
        switch self {
        case .appleHealth:
            "SharpIt ne lira plus tes séances, ton sommeil ni ton cœur depuis Santé. Ce qui est déjà importé est conservé."
        case .appleCalendar:
            "Tes séances ne seront plus copiées dans le calendrier de ton iPhone et le coach ne lira plus tes créneaux occupés."
        case .withings, .google, .strava:
            oauth?.confirmationMessage ?? ""
        }
    }
}
