import Foundation

/// Reads and writes the athlete's profile: identity, thresholds and reading density.
nonisolated protocol AthleteProfileServing: Sendable {
    func athleteProfile(token: String) async throws -> V1AthleteProfile
    /// Sends only the fields of the patch, and returns the profile as saved.
    func patchAthleteProfile(_ patch: AthleteProfilePatch, token: String) async throws -> V1AthleteProfile
    func thresholdHistory(token: String) async throws -> [V1ThresholdSnapshot]
}

/// The weigh-ins behind Corps.
nonisolated protocol BodyCompositionServing: Sendable {
    func bodyComposition(days: Int, token: String) async throws -> [V1BodyMeasurement]
}

/// `/api/athlete-profile` and `/api/body-composition` are web-internal, not `/api/v1`.
/// Known debt, as with `ActivityClient` and `JournalClient` — not a pattern to copy.
actor AthleteProfileClient: AthleteProfileServing, BodyCompositionServing, ThresholdEstimating {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func athleteProfile(token: String) async throws -> V1AthleteProfile {
        try decode(
            V1AthleteProfile.self,
            from: try await send(get("/api/v1/athlete-profile", token: token))
        )
    }

    func patchAthleteProfile(
        _ patch: AthleteProfilePatch,
        token: String
    ) async throws -> V1AthleteProfile {
        // An empty patch would still upsert the row, so nothing is sent for a form the
        // athlete opened and left as it was.
        guard !patch.isEmpty else { return try await athleteProfile(token: token) }

        var request = URLRequest(url: baseURL.appending(path: "/api/v1/athlete-profile"))
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Serialised from the patch's own dictionary rather than encoded from a struct of
        // optionals: the API reads an absent key as "leave it" and an explicit null as
        // "clear it", and `encodeIfPresent` cannot tell those apart.
        request.httpBody = try JSONSerialization.data(withJSONObject: patch.body)

        return try decode(V1AthleteProfile.self, from: try await send(request))
    }

    func thresholdHistory(token: String) async throws -> [V1ThresholdSnapshot] {
        try decode(
            [V1ThresholdSnapshot].self,
            from: try await send(get("/api/v1/athlete-profile/threshold-history", token: token))
        )
    }

    func thresholdPreview(token: String) async throws -> V1ThresholdApplyPreview {
        try decode(
            V1ThresholdApplyPreview.self,
            from: try await send(get("/api/v1/athlete-profile/apply-estimates", token: token))
        )
    }

    /// `{ fields }` names the proposals kept; the server writes only those it still offers. A
    /// 400 carries why nothing was written (`no_estimates`, `unchanged`, `nothing_selected`).
    func applyThresholdEstimates(fields: [V1ThresholdField], token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/athlete-profile/apply-estimates"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields.map(\.rawValue)])

        let (data, status) = try await exchange(request)
        switch status {
        case 200...299: return
        case 401, 403: throw SharpitAPIError.unauthorized
        case 429: throw SharpitAPIError.rateLimited
        case 400...499: throw SharpitAPIError.message(Self.applyRefusal(in: data))
        default: throw SharpitAPIError.server
        }
    }

    /// Garmin is asked live, so the call is given more than the default minute. The server
    /// answers a disconnected account with a 500 and its words (« Compte Garmin non connecté »):
    /// that message is what the athlete reads.
    func importGarminThresholds(token: String) async throws -> V1GarminThresholdImport {
        var request = URLRequest(
            url: baseURL.appending(path: "/api/v1/athlete-profile/import-garmin"),
            timeoutInterval: 120
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, status) = try await exchange(request)
        switch status {
        case 200...299:
            return try decode(V1GarminThresholdImport.self, from: data)
        case 401, 403:
            throw SharpitAPIError.unauthorized
        default:
            if let message = PlannedSessionClient.refusal(in: data) {
                throw SharpitAPIError.message(message)
            }
            throw SharpitAPIError.server
        }
    }

    nonisolated static func applyRefusal(in data: Data) -> String {
        let reason = (try? JSONDecoder().decode(JSONValue.self, from: data))?["reason"]?.string
        if let reason, let refusal = V1ThresholdApplyRefusal(rawValue: reason) {
            return refusal.message
        }
        return PlannedSessionClient.refusal(in: data) ?? "Seuils non appliqués."
    }

    private func exchange(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw SharpitAPIError.transport
        }
    }

    func bodyComposition(days: Int, token: String) async throws -> [V1BodyMeasurement] {
        try decode(
            [V1BodyMeasurement].self,
            from: try await send(get(
                "/api/v1/body-composition",
                query: [URLQueryItem(name: "days", value: String(days))],
                token: token
            ))
        )
    }

    private func get(
        _ path: String,
        query: [URLQueryItem] = [],
        token: String
    ) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url = url.appending(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
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
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AthleteProfileClientError.decoding(String(describing: error))
        }
    }
}

enum AthleteProfileClientError: Error, Equatable, LocalizedError {
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .decoding: "Réponse du profil incompatible"
        }
    }
}
