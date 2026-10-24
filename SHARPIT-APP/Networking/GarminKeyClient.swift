import Foundation

/// `GET /api/v1/garmin/connect` — whether the athlete may add a Garmin Personal API key, and the
/// key's last four characters once one is stored. The key itself never comes back (web ADR-103).
nonisolated struct V1GarminKeyStatus: Decodable, Sendable, Equatable {
    let available: Bool
    let connected: Bool
    let apiKeyLast4: String?

    static let unavailable = V1GarminKeyStatus(available: false, connected: false, apiKeyLast4: nil)
}

nonisolated protocol GarminKeyServing: Sendable {
    func status(token: String) async throws -> V1GarminKeyStatus
    /// Sends the key once; the server checks it with Garmin before keeping it.
    func connect(apiKey: String, token: String) async throws
}

/// The app keeps no copy of the key: it goes from the field to this request and nowhere else.
actor GarminKeyClient: GarminKeyServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func status(token: String) async throws -> V1GarminKeyStatus {
        let data = try await send(request(method: "GET", token: token))
        return try JSONDecoder().decode(V1GarminKeyStatus.self, from: data)
    }

    func connect(apiKey: String, token: String) async throws {
        var request = request(method: "POST", token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["apiKey": apiKey])
        _ = try await send(request)
    }

    private func request(method: String, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/garmin/connect"))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// A 400 is Garmin refusing the key: its message says so. A 403 is the key form closed.
    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        if status == 401 { throw SharpitAPIError.unauthorized }
        if status == 429 { throw SharpitAPIError.rateLimited }
        if status >= 500 { throw SharpitAPIError.server }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String {
            throw SharpitAPIError.message(message)
        }
        throw SharpitAPIError.badRequest
    }
}
