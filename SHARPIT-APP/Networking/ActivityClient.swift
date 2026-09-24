import Foundation

enum ActivityClientError: Error, Equatable, LocalizedError {
    case invalidResponse(status: Int, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let status, let body):
            return "API \(status) — \(body)"
        case .decoding(let message):
            return "Réponse API incompatible — \(message)"
        }
    }
}

protocol ActivityServing: Sendable {
    func activities(token: String) async throws -> [V1ActivityListItem]
    func activities(forceRefresh: Bool, token: String) async throws -> [V1ActivityListItem]
    func activity(id: String, token: String) async throws -> V1ActivityDetail
    func activityStream(id: String, token: String) async throws -> V1ActivityStreamPayload
    func generateNarrative(id: String, token: String) async throws -> V1ActivityDetail
    func updateSubjective(id: String, rpe: Double?, feeling: String?, token: String) async throws
    /// Forgets the cached list. Linking a session changes what each activity says about its
    /// plan, and a list read afterwards must not repeat the old answer.
    func invalidateActivities() async
}

extension ActivityServing {
    func activities(forceRefresh: Bool, token: String) async throws -> [V1ActivityListItem] {
        try await activities(token: token)
    }
    /// Most conformers hold no cache, so the default is to have nothing to forget.
    func invalidateActivities() async {}
}

actor ActivityClient: ActivityServing {
    private let session: URLSession
    private let baseURL: URL
    private var activitiesCache: [V1ActivityListItem]?
    private var detailCache: [String: V1ActivityDetail] = [:]
    private var streamCache: [String: V1ActivityStreamPayload] = [:]

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func activities(token: String) async throws -> [V1ActivityListItem] {
        try await activities(forceRefresh: false, token: token)
    }

    func activities(forceRefresh: Bool, token: String) async throws -> [V1ActivityListItem] {
        if !forceRefresh, let activitiesCache {
            return activitiesCache
        }
        let activities: [V1ActivityListItem] = try await request(
            path: "/api/v1/activities",
            queryItems: [],
            token: token
        )
        activitiesCache = activities
        return activities
    }

    func activity(id: String, token: String) async throws -> V1ActivityDetail {
        if let cached = detailCache[id] {
            return cached
        }
        let detail: V1ActivityDetail = try await request(path: "/api/v1/activities/\(id)", queryItems: [], token: token)
        detailCache[id] = detail
        return detail
    }

    func activityStream(id: String, token: String) async throws -> V1ActivityStreamPayload {
        if let cached = streamCache[id] {
            return cached
        }
        let stream: V1ActivityStreamPayload = try await request(path: "/api/v1/activities/\(id)/streams", queryItems: [], token: token)
        streamCache[id] = stream
        return stream
    }

    func invalidateActivities() {
        activitiesCache = nil
    }

    func generateNarrative(id: String, token: String) async throws -> V1ActivityDetail {
        try await request(
            path: "/api/v1/activities/\(id)/narrative",
            method: "POST",
            body: Data(#"{"wait":true}"#.utf8),
            queryItems: [],
            token: token
        )
    }

    func updateSubjective(id: String, rpe: Double?, feeling: String?, token: String) async throws {
        var payload: [String: Any] = [:]
        payload["rpe"] = rpe ?? NSNull()
        payload["feeling"] = feeling ?? NSNull()
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await requestData(path: "/api/v1/activities/\(id)", body: body, token: token)
        detailCache[id] = nil
        activitiesCache = nil
    }

    private func requestData(path: String, body: Data, token: String) async throws {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw SharpitAPIError.server
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = body
        request.setValue("Bear" + "er " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ActivityClientError.invalidResponse(status: status, body: "Mise à jour impossible")
        }
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem],
        token: String
    ) async throws -> T {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw SharpitAPIError.server
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = body
        request.setValue("Bear" + "er " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            break
        case 401:
            throw SharpitAPIError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8) ?? "Réponse illisible"
            throw ActivityClientError.invalidResponse(status: status, body: String(body.prefix(180)))
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ActivityClientError.decoding(String(describing: error))
        }
    }
}
