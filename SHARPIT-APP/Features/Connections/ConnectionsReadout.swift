import Foundation
import SwiftUI

/// The words Connexions uses for each data source, kept apart from the view so what a badge
/// says — and which tone it takes — is decided once and can be tested.
///
/// A badge, not a sentence: a status changing length ("Connecté" → "Connecté · synchronisé
/// il y a 12 min" → "Connecté · synchronisé il y a 3 h") used to reflow the whole section on
/// every tick. The recency itself still matters, but it belongs on the toast that shows while
/// a check is under way, not on a row that reads every minute of the athlete's life.
enum ConnectionsReadout {
    struct Badge: Equatable {
        let text: String
        let tone: Tone

        enum Tone {
            case positive
            case neutral
            case negative

            var color: Color {
                switch self {
                case .positive: SharpitColor.signalRecovery
                case .neutral: SharpitColor.mutedForeground
                case .negative: SharpitColor.signalRisk
                }
            }
        }
    }

    static func garmin(status: V1SyncStatus?) -> Badge {
        guard let status else { return Badge(text: "—", tone: .neutral) }
        guard status.providers.contains(where: { $0.key == "garmin" }) else {
            return Badge(text: "Non connecté", tone: .neutral)
        }
        return Badge(text: "Connecté", tone: .positive)
    }

    /// The history import's second line: what the button does, or how the last run went.
    static func garminHistory(_ state: GarminHistoryImport.State) -> String {
        switch state {
        case .idle: "Récupère les activités antérieures"
        case .importing: "Import en cours…"
        case .finished(let imported):
            imported == 0
                ? "Historique à jour"
                : "\(imported) activité\(imported > 1 ? "s" : "") importée\(imported > 1 ? "s" : "")"
        case .failed: "Import interrompu — réessaie"
        }
    }

    /// A status line and whether it is a problem the switch does not show.
    struct Line: Equatable {
        let text: String
        let isProblem: Bool
    }

    /// What Apple Health is for, unless something stops it: the switch already says on or off.
    static func appleHealthSubtitle(isAvailable: Bool, state: AppleHealthSource.State) -> Line {
        guard isAvailable else { return Line(text: "Indisponible sur cet iPhone", isProblem: false) }
        if case .failed(let message) = state { return Line(text: message, isProblem: true) }
        return Line(text: "Séances, sommeil et cœur de ta montre", isProblem: false)
    }

    static func appleCalendarSubtitle(state: AppleCalendarSource.State) -> Line {
        if case .failed(let message) = state { return Line(text: message, isProblem: true) }
        return Line(text: "Séances planifiées et créneaux occupés", isProblem: false)
    }

    /// A source linked on the web, read as connected: what it brings, in the positive tone.
    static func connected(_ source: DisconnectableSource) -> Badge {
        Badge(text: source.purpose, tone: .positive)
    }

    /// Withings and Google Agenda are linked on the web only: the footer says where, and once
    /// one is here, that a tap disconnects it — never a dead end.
    static func webSourcesFooter(connected: [DisconnectableSource]) -> String {
        let webOnly = connected.filter { $0 != .garmin }
        if webOnly.isEmpty {
            return "Withings et Google Agenda se connectent depuis sharpit.app ; une fois reliés, ils apparaissent ici."
        }
        return "Touche une source reliée pour la déconnecter. Withings et Google Agenda se connectent depuis sharpit.app."
    }

    /// A disconnection that failed for good: the cause when the server gave one, else the fix.
    static func disconnectFailure(_ source: DisconnectableSource, error: any Error) -> String {
        switch error as? SharpitAPIError {
        case .transport?:
            "Pas de connexion internet : \(source.name) est toujours relié. Réessaie."
        case .unauthorized?:
            "Ta session a expiré. Reconnecte-toi, puis réessaie."
        case .message(let text)?:
            text
        default:
            "Déconnexion de \(source.name) impossible pour le moment. Réessaie dans un instant."
        }
    }

}
