import Foundation

nonisolated protocol ActivityStatusServing: Sendable {
    func activityStatus(token: String) async throws -> V1ActivityStatusStore
    func setActivityStatus(
        _ write: V1ActivityStatusWrite,
        token: String
    ) async throws -> V1ActivityStatusStore
    /// Each day's mode from `from` to `to`, both `yyyy-MM-dd` and included.
    func activityStatusDays(from: String, to: String, token: String) async throws -> [V1ActivityStatusDay]
    /// Sets a past day's mode; the current mode is left as it is.
    func setActivityStatus(
        _ status: ActivityStatusId,
        on day: String,
        token: String
    ) async throws -> V1ActivityStatusDay
}

actor ActivityStatusClient: ActivityStatusServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func activityStatus(token: String) async throws -> V1ActivityStatusStore {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/activity-status"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    func setActivityStatus(
        _ write: V1ActivityStatusWrite,
        token: String
    ) async throws -> V1ActivityStatusStore {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/activity-status"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(write)
        return try await send(request)
    }

    func activityStatusDays(from: String, to: String, token: String) async throws -> [V1ActivityStatusDay] {
        var components = URLComponents(
            url: baseURL.appending(path: "/api/v1/activity-status/days"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
        guard let url = components?.url else { throw SharpitAPIError.server }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, as: V1ActivityStatusDaysEnvelope.self).days
    }

    func setActivityStatus(
        _ status: ActivityStatusId,
        on day: String,
        token: String
    ) async throws -> V1ActivityStatusDay {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/activity-status"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(V1ActivityStatusDay(day: day, status: status))
        return try await send(request, as: V1ActivityStatusDayEnvelope.self).day
    }

    private func send(_ request: URLRequest) async throws -> V1ActivityStatusStore {
        try await send(request, as: V1ActivityStatusEnvelope.self).store
    }

    private func send<Envelope: Decodable>(_ request: URLRequest, as _: Envelope.Type) async throws -> Envelope {
        let data: Data
        let response: URLResponse
        (data, response) = try await session.sharpitData(for: request)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 { throw SharpitAPIError.unauthorized }
            throw SharpitAPIError.server
        }
        do {
            return try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ActivityStatusClientError.decoding(String(describing: error))
        }
    }
}

enum ActivityStatusClientError: Error, Equatable, LocalizedError {
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .decoding: String(localized: "Réponse du statut d'activité incompatible")
        }
    }
}
