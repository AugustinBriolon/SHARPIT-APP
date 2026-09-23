import CloudKit
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

    /// A status line and whether it is a problem the switch does not show.
    struct Line: Equatable {
        let text: String
        let isProblem: Bool
    }

    /// What Apple Health is for, unless something stops it: the switch already says on or off.
    static func appleHealthSubtitle(isAvailable: Bool, state: AppleHealthSource.State) -> Line {
        guard isAvailable else { return Line(text: "Indisponible sur cet iPhone", isProblem: false) }
        if case .failed(let message) = state { return Line(text: message, isProblem: true) }
        return Line(text: "Complète Garmin entre deux synchros", isProblem: false)
    }

    static func iCloud(_ status: CKAccountStatus?) -> String {
        guard let status else { return "—" }
        switch status {
        case .available: return "Actif"
        case .noAccount: return "Aucun compte"
        case .restricted: return "Restreint"
        case .temporarilyUnavailable: return "Indisponible"
        case .couldNotDetermine: return "Inconnu"
        @unknown default: return "Inconnu"
        }
    }
}
