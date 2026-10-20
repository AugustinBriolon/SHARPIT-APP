import AuthenticationServices
import SwiftUI

/// How an OAuth provider connection ended, read from
/// `/connect/<provider>/callback?<provider>=<status>` — same words for the in-app session
/// and for a plain browser that lands on the apex callback.
enum ProviderOAuthConnectOutcome: Equatable {
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

    var isLinked: Bool {
        self == .connected || self == .alreadyConnected
    }

    func message(for source: DisconnectableSource) -> String {
        switch self {
        case .connected: String(localized: "\(source.name) connecté — synchronisation en cours…")
        case .alreadyConnected: String(localized: "\(source.name) est déjà connecté")
        case .cancelled: String(localized: "Connexion \(source.name) annulée")
        case .consentRequired: String(localized: "Autorisation requise pour \(source.name)")
        case .invalidState: String(localized: "Session \(source.name) expirée")
        case .denied: String(localized: "Connexion \(source.name) refusée")
        case .failed: String(localized: "Connexion \(source.name) impossible")
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

/// Connects Strava / Google / Withings inside the app: an authentication session opens the
/// apex handoff, the athlete signs in at the provider, and the session closes on the
/// Associated Domains callback.
enum ProviderOAuthConnect {
    typealias Authenticate = (_ url: URL, _ callbackPath: String) async throws -> URL

    static func callbackPath(for source: DisconnectableSource) -> String {
        "/connect/\(source.rawValue)/callback"
    }

    static func run(
        source: DisconnectableSource,
        client: any ProviderOAuthHandoffServing,
        tokenProvider: () async throws -> String,
        authenticate: Authenticate
    ) async -> ProviderOAuthConnectOutcome {
        let entry: URL
        do {
            entry = try await client.providerHandoffURL(source, token: try await tokenProvider())
        } catch {
            #if DEBUG
            print("[ProviderOAuthConnect] providerHandoffURL failed for \(source.rawValue): \(error)")
            #endif
            return .failed
        }

        do {
            let callback = try await authenticate(entry, callbackPath(for: source))
            guard case .oauthCallback(let provider, let status) = IncomingLink.parse(callback),
                  provider == source.rawValue
            else { return .failed }
            return ProviderOAuthConnectOutcome(status: status)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return .cancelled
        } catch {
            #if DEBUG
            print("[ProviderOAuthConnect] authenticate failed for \(source.rawValue): \(error)")
            #endif
            return .failed
        }
    }
}

extension WebAuthenticationSession {
    /// Ephemeral: the sheet must sign in as the app's athlete via the one-time ticket.
    func providerOAuthConnect(_ url: URL, callbackPath: String) async throws -> URL {
        try await authenticate(
            using: url,
            callback: .https(host: IncomingLink.trustedHost, path: callbackPath),
            preferredBrowserSession: .ephemeral,
            additionalHeaderFields: [:]
        )
    }
}
