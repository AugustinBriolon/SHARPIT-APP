import Foundation

/// The athlete's legal and processing consents, as `/api/v1/privacy/consent` returns them
/// (the web's `serializeConsentRow`).
///
/// `currentPrivacyVersion` comes from the server, so the app never hardcodes which version of
/// the documents is in force: when the web publishes a new one, the wall comes back on its own.
nonisolated struct V1PrivacyConsents: Codable, Sendable, Equatable {
    var termsAcceptedAt: Date?
    var privacyAcceptedAt: Date?
    var privacyVersion: String?
    var healthDataConsentAt: Date?
    var aiProcessingConsentAt: Date?
    var unofficialProvidersAckAt: Date?
    var currentPrivacyVersion: String

    /// Why the wall stands in front of the app — the web's `resolveConsentWallReason`.
    nonisolated enum WallReason: Equatable, Sendable {
        /// Never accepted, or a newer version of the documents is in force.
        case documents
        /// The documents are current but the health consent was withdrawn.
        case healthWithdrawn
    }

    init(
        termsAcceptedAt: Date? = nil,
        privacyAcceptedAt: Date? = nil,
        privacyVersion: String? = nil,
        healthDataConsentAt: Date? = nil,
        aiProcessingConsentAt: Date? = nil,
        unofficialProvidersAckAt: Date? = nil,
        currentPrivacyVersion: String
    ) {
        self.termsAcceptedAt = termsAcceptedAt
        self.privacyAcceptedAt = privacyAcceptedAt
        self.privacyVersion = privacyVersion
        self.healthDataConsentAt = healthDataConsentAt
        self.aiProcessingConsentAt = aiProcessingConsentAt
        self.unofficialProvidersAckAt = unofficialProvidersAckAt
        self.currentPrivacyVersion = currentPrivacyVersion
    }

    private enum CodingKeys: String, CodingKey {
        case termsAcceptedAt, privacyAcceptedAt, privacyVersion, healthDataConsentAt
        case aiProcessingConsentAt, unofficialProvidersAckAt, currentPrivacyVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        termsAcceptedAt = Self.date(in: container, forKey: .termsAcceptedAt)
        privacyAcceptedAt = Self.date(in: container, forKey: .privacyAcceptedAt)
        privacyVersion = try container.decodeIfPresent(String.self, forKey: .privacyVersion)
        healthDataConsentAt = Self.date(in: container, forKey: .healthDataConsentAt)
        aiProcessingConsentAt = Self.date(in: container, forKey: .aiProcessingConsentAt)
        unofficialProvidersAckAt = Self.date(in: container, forKey: .unofficialProvidersAckAt)
        currentPrivacyVersion = try container.decode(String.self, forKey: .currentPrivacyVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(termsAcceptedAt?.toAPI, forKey: .termsAcceptedAt)
        try container.encodeIfPresent(privacyAcceptedAt?.toAPI, forKey: .privacyAcceptedAt)
        try container.encodeIfPresent(privacyVersion, forKey: .privacyVersion)
        try container.encodeIfPresent(healthDataConsentAt?.toAPI, forKey: .healthDataConsentAt)
        try container.encodeIfPresent(aiProcessingConsentAt?.toAPI, forKey: .aiProcessingConsentAt)
        try container.encodeIfPresent(unofficialProvidersAckAt?.toAPI, forKey: .unofficialProvidersAckAt)
        try container.encode(currentPrivacyVersion, forKey: .currentPrivacyVersion)
    }

    private static func date(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key), !raw.isEmpty else {
            return nil
        }
        return try? Date.fromAPI(raw)
    }

    /// The web's `needsLegalConsentFromProfile`: both documents accepted, at the version in
    /// force, and the health consent given — health is required, not optional (art. 9).
    var wallReason: WallReason? {
        guard termsAcceptedAt != nil, privacyAcceptedAt != nil, privacyVersion == currentPrivacyVersion else {
            return .documents
        }
        return healthDataConsentAt == nil ? .healthWithdrawn : nil
    }

    var hasHealthConsent: Bool { healthDataConsentAt != nil }
    var hasAIConsent: Bool { aiProcessingConsentAt != nil }
    var hasUnofficialProvidersAck: Bool { unofficialProvidersAckAt != nil }
}

/// One consent write. An absent field leaves that consent as it is, `true` grants it and
/// `false` withdraws it — the web's `ConsentUpdateInput`, so the body is built key by key.
nonisolated struct PrivacyConsentUpdate: Equatable, Sendable {
    var acceptLegal = false
    var healthDataConsent: Bool?
    var aiProcessingConsent: Bool?
    var unofficialProvidersAck: Bool?

    /// What the wall sends: the documents and the health consent together — the server refuses
    /// one without the other — plus whichever optional consents were ticked. An unticked
    /// optional stays absent, never `false`, as on the web.
    static func wall(ai: Bool, unofficialProviders: Bool) -> PrivacyConsentUpdate {
        PrivacyConsentUpdate(
            acceptLegal: true,
            healthDataConsent: true,
            aiProcessingConsent: ai ? true : nil,
            unofficialProvidersAck: unofficialProviders ? true : nil
        )
    }

    var body: [String: Bool] {
        var body: [String: Bool] = [:]
        if acceptLegal { body["acceptLegal"] = true }
        if let healthDataConsent { body["healthDataConsent"] = healthDataConsent }
        if let aiProcessingConsent { body["aiProcessingConsent"] = aiProcessingConsent }
        if let unofficialProvidersAck { body["unofficialProvidersAck"] = unofficialProvidersAck }
        return body
    }
}

nonisolated protocol PrivacyConsentServing: Sendable {
    func consents(token: String) async throws -> V1PrivacyConsents
    /// Writes the update and returns the consents as saved.
    func updateConsents(_ update: PrivacyConsentUpdate, token: String) async throws -> V1PrivacyConsents
}

/// `/api/v1/privacy/consent` — the native contract for the web's handler (ADR-040).
actor PrivacyConsentClient: PrivacyConsentServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func consents(token: String) async throws -> V1PrivacyConsents {
        try await send(makeRequest(method: "GET", token: token))
    }

    func updateConsents(_ update: PrivacyConsentUpdate, token: String) async throws -> V1PrivacyConsents {
        var request = makeRequest(method: "POST", token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: update.body)
        return try await send(request)
    }

    private func makeRequest(method: String, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/privacy/consent"))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private nonisolated struct Envelope: Decodable {
        let consents: V1PrivacyConsents
    }

    private func send(_ request: URLRequest) async throws -> V1PrivacyConsents {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { throw SharpitAPIError.unauthorized }
            throw SharpitAPIError.server
        }
        do {
            return try JSONDecoder().decode(Envelope.self, from: data).consents
        } catch {
            throw SharpitAPIError.server
        }
    }
}
