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
    /// The sources linked: the OAuth ones the server reports, the iPhone's own from their switches.
    static func linkedSources(
        providerKeys: [String],
        appleHealthEnabled: Bool,
        appleCalendarLinked: Bool
    ) -> Set<ManagedSource> {
        var sources = Set(ManagedSource.allCases.filter { source in
            source.oauth.map { providerKeys.contains($0.statusKey) } ?? false
        })
        if appleHealthEnabled { sources.insert(.appleHealth) }
        if appleCalendarLinked { sources.insert(.appleCalendar) }
        return sources
    }

    /// Paramètres' line under « Sources de données »: the one source by name, else how many.
    static func sourcesSummary(_ linked: Set<ManagedSource>) -> String {
        switch linked.count {
        case 0: String(localized: "Aucune source connectée")
        case 1: String(localized: "\(linked.first!.name) connecté")
        default: String(localized: "\(linked.count) sources connectées")
        }
    }

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

    /// A status line and whether it is a problem the switch does not show.
    struct Line: Equatable {
        let text: String
        let isProblem: Bool
    }

    /// What Apple Health is for, unless something stops it: the switch already says on or off.
    static func appleHealthSubtitle(isAvailable: Bool, state: AppleHealthSource.State) -> Line {
        guard isAvailable else { return Line(text: String(localized: "Indisponible sur cet appareil"), isProblem: false) }
        if case .failed(let message) = state { return Line(text: message, isProblem: true) }
        return Line(text: ManagedSource.appleHealth.purpose, isProblem: false)
    }

    static func appleCalendarSubtitle(state: AppleCalendarSource.State) -> Line {
        if case .failed(let message) = state { return Line(text: message, isProblem: true) }
        return Line(text: ManagedSource.appleCalendar.purpose, isProblem: false)
    }

    /// A source linked, read as connected: what it brings, in the positive tone.
    static func connected(_ source: DisconnectableSource) -> Badge {
        Badge(text: source.purpose, tone: .positive)
    }

    static func disconnected(_: DisconnectableSource) -> Badge {
        Badge(text: String(localized: "Non connecté"), tone: .neutral)
    }

    static let sourcesFooter =
        String(localized: "Touche une source pour la gérer ou la déconnecter. Le + en ajoute une.")

    /// Connected sources first, then the ones the « + » sheet offers — each in the screen's order.
    /// A source the device cannot run (Apple Health on an iPad) is never offered.
    static func split(
        linked: Set<ManagedSource>,
        unavailable: Set<ManagedSource> = []
    ) -> (connected: [ManagedSource], available: [ManagedSource]) {
        let connected = ManagedSource.allCases.filter { linked.contains($0) }
        let available = ManagedSource.allCases.filter { !linked.contains($0) && !unavailable.contains($0) }
        return (connected, available)
    }

    /// Garmin's row: its masked key, the only part of it the app ever sees.
    static func garminKeyLine(last4: String?) -> Line {
        guard let last4, !last4.isEmpty else {
            return Line(text: String(localized: "Clé API à renouveler"), isProblem: true)
        }
        return Line(text: String(localized: "Clé ••••\(last4)"), isProblem: false)
    }

    /// A key Garmin refused says why (the server's message); anything else, the usual fix.
    static func garminKeyFailure(_ error: any Error) -> String {
        if case .message(let text)? = error as? SharpitAPIError { return text }
        return SharpitErrorGuidance.message(for: error, subject: String(localized: "La connexion Garmin"))
    }

    /// Choosing between sources only matters from two on.
    static func offersPriorities(connectedCount: Int) -> Bool { connectedCount >= 2 }

    /// A disconnection that failed for good: the cause when the server gave one, else the fix.
    static func disconnectFailure(_ source: DisconnectableSource, error: any Error) -> String {
        switch error as? SharpitAPIError {
        case .transport?:
            String(localized: "Pas de connexion internet : \(source.name) est toujours relié. Réessaie.")
        case .unauthorized?:
            String(localized: "Ta session a expiré. Reconnecte-toi, puis réessaie.")
        case .message(let text)?:
            text
        default:
            String(localized: "Déconnexion de \(source.name) impossible pour le moment. Réessaie dans un instant.")
        }
    }

}
