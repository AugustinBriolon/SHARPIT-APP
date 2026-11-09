import Foundation

/// One declared health ground (SHARPIT ADR-124), in the web's `putHealthGroundsSchema` shape.
nonisolated struct HealthGroundInput: Codable, Equatable, Hashable, Sendable {
    let key: String
    var stage: String
    var details: String?
}

nonisolated protocol HealthGroundWriting: Sendable {
    /// Replaces the athlete's whole declared set.
    func replaceHealthGrounds(_ grounds: [HealthGroundInput], token: String) async throws
}

/// `/api/v1/health-grounds` — health data, written once the health consent is given.
actor HealthGroundClient: HealthGroundWriting {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    private struct Body: Encodable {
        let grounds: [HealthGroundInput]
    }

    func replaceHealthGrounds(_ grounds: [HealthGroundInput], token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/health-grounds"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(grounds: grounds))
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
    }
}
