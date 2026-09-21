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
actor AthleteProfileClient: AthleteProfileServing, BodyCompositionServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func athleteProfile(token: String) async throws -> V1AthleteProfile {
        try await decode(
            V1AthleteProfile.self,
            from: try await send(get("/api/athlete-profile", token: token))
        )
    }

    func patchAthleteProfile(
        _ patch: AthleteProfilePatch,
        token: String
    ) async throws -> V1AthleteProfile {
        // An empty patch would still upsert the row, so nothing is sent for a form the
        // athlete opened and left as it was.
        guard !patch.isEmpty else { return try await athleteProfile(token: token) }

        var request = URLRequest(url: baseURL.appending(path: "/api/athlete-profile"))
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Serialised from the patch's own dictionary rather than encoded from a struct of
        // optionals: the API reads an absent key as "leave it" and an explicit null as
        // "clear it", and `encodeIfPresent` cannot tell those apart.
        request.httpBody = try JSONSerialization.data(withJSONObject: patch.body)

        return try await decode(V1AthleteProfile.self, from: try await send(request))
    }

    func thresholdHistory(token: String) async throws -> [V1ThresholdSnapshot] {
        try await decode(
            [V1ThresholdSnapshot].self,
            from: try await send(get("/api/athlete-profile/threshold-history", token: token))
        )
    }

    func bodyComposition(days: Int, token: String) async throws -> [V1BodyMeasurement] {
        try await decode(
            [V1BodyMeasurement].self,
            from: try await send(get(
                "/api/body-composition",
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
