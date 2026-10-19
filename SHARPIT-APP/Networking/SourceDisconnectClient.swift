import Foundation

/// A third-party source the athlete can unlink from Paramètres › Sources de données — the web's
/// `*/disconnect` handlers, through their `/api/v1` contracts (ADR-040). The server revokes the
/// grant at the provider where it can (Withings, Google), forgets the account and takes the
/// source out of the per-category priorities. What was already imported stays.
nonisolated enum DisconnectableSource: String, CaseIterable, Identifiable, Sendable {
    case strava
    case withings
    case google

    var id: String { rawValue }

    /// The key `/api/v1/sync-status` lists a connected source under.
    var statusKey: String { rawValue }

    /// `POST /api/v1/<source>/disconnect`.
    var path: String { "/api/v1/\(rawValue)/disconnect" }

    var name: String {
        switch self {
        case .strava: String(localized: "Strava")
        case .withings: String(localized: "Withings")
        case .google: String(localized: "Google Agenda")
        }
    }

    var logo: ProviderLogo.Provider {
        switch self {
        case .strava: .strava
        case .withings: .withings
        case .google: .google
        }
    }

    /// What the source brings, on its row's second line once connected.
    var purpose: String {
        switch self {
        case .strava: String(localized: "Séances et activités")
        case .withings: String(localized: "Poids et composition corporelle")
        case .google: String(localized: "Planning et disponibilités")
        }
    }

    /// The web's confirmation title (`modal-content-*.tsx`).
    var confirmationTitle: String { String(localized: "Déconnecter \(name) ?") }

    /// What stops, then what stays — the athlete decides on facts, never on a warning tone.
    var confirmationMessage: String {
        switch self {
        case .strava:
            String(localized: "SharpIt ne recevra plus tes activités Strava et l'accès est révoqué chez Strava. Ce qui est déjà importé est conservé.")
        case .withings:
            String(localized: "SharpIt ne recevra plus tes pesées ni ta composition corporelle, et l'accès est révoqué chez Withings. Les mesures importées sont conservées.")
        case .google:
            String(localized: "Tes séances ne seront plus écrites dans ton agenda et le coach ne lira plus tes disponibilités ; l'accès est révoqué chez Google. Les événements déjà créés restent dans l'agenda.")
        }
    }

    var confirmLabel: String { String(localized: "Déconnecter \(name)") }

    var disconnectedMessage: String { String(localized: "\(name) déconnecté") }

    /// The sources that read as connected in a sync status, in the screen's order.
    static func connected(in status: V1SyncStatus?) -> [DisconnectableSource] {
        guard let status else { return [] }
        let keys = Set(status.providers.map(\.key))
        return allCases.filter { keys.contains($0.statusKey) }
    }

    /// The sources the phone connects itself, in the web's Compte → Sources order.
    static let oauthConnectable: [DisconnectableSource] = [.withings, .google, .strava]

    var connectsViaOAuthHandoff: Bool { Self.oauthConnectable.contains(self) }
}

nonisolated protocol SourceDisconnecting: Sendable {
    func disconnect(_ source: DisconnectableSource, token: String) async throws
}

/// `POST /api/v1/{strava,withings,google}/disconnect`.
actor SourceDisconnectClient: SourceDisconnecting {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func disconnect(_ source: DisconnectableSource, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: source.path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(status) else { return }
        if status == 401 || status == 403 { throw SharpitAPIError.unauthorized }
        if status == 429 { throw SharpitAPIError.rateLimited }
        if status >= 500 { throw SharpitAPIError.server }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String {
            throw SharpitAPIError.message(message)
        }
        throw SharpitAPIError.badRequest
    }
}
