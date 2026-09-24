import Foundation

/// `GET /api/v1/pro` — the tier, the perks as the web words them, and the subscription behind
/// the tier (`projectV1Pro`, SHARPIT ADR-044). The app never duplicates the perks' copy.
nonisolated struct V1Pro: Decodable, Sendable, Equatable {
    let tier: String
    let perks: [V1ProPerk]
    let subscription: V1ProSubscription?

    var isPro: Bool { tier == "PRO" }

    init(tier: String, perks: [V1ProPerk] = [], subscription: V1ProSubscription? = nil) {
        self.tier = tier
        self.perks = perks
        self.subscription = subscription
    }

    private enum CodingKeys: String, CodingKey {
        case tier, perks, subscription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tier = try container.decode(String.self, forKey: .tier)
        // A perk status this build does not know is skipped rather than failing the page.
        perks = (try? container.decode([Lossy<V1ProPerk>].self, forKey: .perks))?.compactMap(\.value) ?? []
        subscription = try? container.decodeIfPresent(V1ProSubscription.self, forKey: .subscription)
    }
}

nonisolated struct V1ProPerk: Decodable, Sendable, Equatable, Identifiable {
    nonisolated enum Status: String, Decodable, Sendable {
        case pro
        case included
        case planned
    }

    let id: String
    let title: String
    let description: String
    let status: Status
}

nonisolated struct V1ProSubscription: Decodable, Sendable, Equatable {
    /// `active`, `grace_period`, `billing_retry`, `expired`, `revoked`.
    let status: String
    /// `apple`, `stripe`, `manual`.
    let source: String
    let renewsAt: Date?
    let expiresAt: Date?
    let willRenew: Bool

    private enum CodingKeys: String, CodingKey {
        case status, source, renewsAt, expiresAt, willRenew
    }

    init(status: String, source: String, renewsAt: Date? = nil, expiresAt: Date? = nil, willRenew: Bool = false) {
        self.status = status
        self.source = source
        self.renewsAt = renewsAt
        self.expiresAt = expiresAt
        self.willRenew = willRenew
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        source = try container.decode(String.self, forKey: .source)
        renewsAt = (try? container.decodeIfPresent(String.self, forKey: .renewsAt)).flatMap { try? Date.fromAPI($0) }
        expiresAt = (try? container.decodeIfPresent(String.self, forKey: .expiresAt)).flatMap { try? Date.fromAPI($0) }
        willRenew = (try? container.decodeIfPresent(Bool.self, forKey: .willRenew)) ?? false
    }
}

nonisolated protocol ProServing: Sendable {
    func pro(token: String) async throws -> V1Pro
    /// The UUID StoreKit carries as `appAccountToken`, stable per athlete.
    func appAccountToken(token: String) async throws -> UUID
    /// Sends a signed StoreKit transaction for the web to verify; answers with the tier after it.
    func verify(signedTransaction: String, signedRenewalInfo: String?, token: String) async throws -> V1Pro
}

/// `/api/v1/pro` and `/api/v1/billing/apple/*`. The web verifies every transaction against
/// Apple's certificate chain and derives the tier; the app is never the authority on it.
actor ProClient: ProServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func pro(token: String) async throws -> V1Pro {
        try await send(V1Pro.self, path: "/api/v1/pro", method: "GET", body: nil, token: token)
    }

    func appAccountToken(token: String) async throws -> UUID {
        let answer = try await send(
            AppAccountTokenAnswer.self,
            path: "/api/v1/billing/apple/app-account-token",
            method: "POST",
            body: nil,
            token: token
        )
        guard let uuid = UUID(uuidString: answer.appAccountToken) else { throw SharpitAPIError.server }
        return uuid
    }

    func verify(signedTransaction: String, signedRenewalInfo: String?, token: String) async throws -> V1Pro {
        var payload = ["signedTransaction": signedTransaction]
        if let signedRenewalInfo { payload["signedRenewalInfo"] = signedRenewalInfo }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await send(V1Pro.self, path: "/api/v1/billing/apple/verify", method: "POST", body: body, token: token)
    }

    private nonisolated struct AppAccountTokenAnswer: Decodable {
        let appAccountToken: String
    }

    private func send<Payload: Decodable>(
        _: Payload.Type,
        path: String,
        method: String,
        body: Data?,
        token: String
    ) async throws -> Payload {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: break
        case 401: throw SharpitAPIError.unauthorized
        case 400, 409: throw SharpitAPIError.badRequest
        default: throw SharpitAPIError.server
        }
        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw SharpitAPIError.server
        }
    }
}
