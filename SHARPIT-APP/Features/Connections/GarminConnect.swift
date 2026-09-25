import AuthenticationServices
import SwiftUI

/// How a Garmin connection ended, read from `/connect/garmin/callback?garmin=<status>` — the
/// web's `GarminHandoffStatus`. The same outcome comes back from the in-app session and from a
/// universal link, so both say it with the same words.
enum GarminConnectOutcome: Equatable {
    case connected
    case alreadyConnected
    case cancelled
    case consentRequired
    case invalidState
    case denied
    case failed

    init(status: String?) {
        switch status {
        case "connected": self = .connected
        case "already_connected": self = .alreadyConnected
        case "cancelled": self = .cancelled
        case "consent_required": self = .consentRequired
        case "invalid_state": self = .invalidState
        case "denied": self = .denied
        default: self = .failed
        }
    }

    /// Garmin is (now) linked: the source list and the data are worth reading again.
    var isLinked: Bool {
        self == .connected || self == .alreadyConnected
    }

    var message: String {
        switch self {
        case .connected: "Garmin connecté — synchronisation en cours…"
        case .alreadyConnected: "Garmin est déjà connecté"
        case .cancelled: "Connexion Garmin annulée"
        case .consentRequired: "Autorisation requise pour Garmin"
        case .invalidState: "Session Garmin expirée"
        case .denied: "Connexion Garmin refusée"
        case .failed: "Connexion Garmin impossible"
        }
    }

    var symbol: String {
        switch self {
        case .connected, .alreadyConnected: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        default: "exclamationmark.triangle"
        }
    }

    var tone: SharpitToastTone {
        switch self {
        case .connected, .alreadyConnected: .success
        case .cancelled: .syncing
        default: .error
        }
    }

    var toastDuration: TimeInterval {
        switch self {
        case .alreadyConnected, .cancelled: 3
        default: 4
        }
    }
}

/// Connects Garmin inside the app (SHARPIT ADR-047): an authentication session opens the web's
/// Garmin handoff on the apex, the athlete signs in on Garmin's own page, and the session closes
/// on the callback the apex AASA declares. The password never reaches SharpIt.
enum GarminConnect {
    /// Opens `url` in an authentication session and returns the URL it closed on.
    typealias Authenticate = (_ url: URL) async throws -> URL

    nonisolated static let callbackPath = "/connect/garmin/callback"

    static func run(
        client: any GarminHandoffServing,
        tokenProvider: () async throws -> String,
        authenticate: Authenticate
    ) async -> GarminConnectOutcome {
        let entry: URL
        do {
            entry = try await client.garminHandoffURL(token: try await tokenProvider())
        } catch {
            return .failed
        }

        do {
            let callback = try await authenticate(entry)
            guard case .garminCallback(let status) = IncomingLink.parse(callback) else { return .failed }
            return GarminConnectOutcome(status: status)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return .cancelled
        } catch {
            return .failed
        }
    }
}

extension WebAuthenticationSession {
    /// Ephemeral on purpose: the sheet must sign in as the app's athlete, through the one-time
    /// ticket, never reuse whoever is signed in to SharpIt in Safari.
    func garminConnect(_ url: URL) async throws -> URL {
        try await authenticate(
            using: url,
            callback: .https(host: IncomingLink.trustedHost, path: GarminConnect.callbackPath),
            preferredBrowserSession: .ephemeral,
            additionalHeaderFields: [:]
        )
    }
}
