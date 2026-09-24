import Foundation

nonisolated protocol ActivityStatusServing: Sendable {
    func activityStatus(token: String) async throws -> V1ActivityStatusStore
    func setActivityStatus(
        _ write: V1ActivityStatusWrite,
        token: String
    ) async throws -> V1ActivityStatusStore
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

    private func send(_ request: URLRequest) async throws -> V1ActivityStatusStore {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 { throw SharpitAPIError.unauthorized }
            throw SharpitAPIError.server
        }
        do {
            return try JSONDecoder().decode(V1ActivityStatusEnvelope.self, from: data).store
        } catch {
            throw ActivityStatusClientError.decoding(String(describing: error))
        }
    }
}

enum ActivityStatusClientError: Error, Equatable, LocalizedError {
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .decoding: "Réponse du statut d'activité incompatible"
        }
    }
}
