import Foundation

/// Reads and writes the athlete's evaluation of a brick, by its group.
protocol BrickEvaluationServing: Sendable {
    func evaluation(brickGroupId: String, token: String) async throws -> V1BrickEvaluation?
    /// Replaces every field: nil clears one.
    func save(_ evaluation: V1BrickEvaluation, token: String) async throws
}

actor BrickEvaluationClient: BrickEvaluationServing {
    private nonisolated static let path = "/api/v1/planned-sessions/brick/evaluation"

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func evaluation(brickGroupId: String, token: String) async throws -> V1BrickEvaluation? {
        guard var components = URLComponents(
            url: baseURL.appending(path: Self.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        components.queryItems = [URLQueryItem(name: "groupId", value: brickGroupId)]
        guard let url = components.url else { throw SharpitAPIError.server }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(V1BrickEvaluationEnvelope.self, from: data).evaluation
        } catch {
            throw SharpitAPIError.server
        }
    }

    func save(_ evaluation: V1BrickEvaluation, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: Self.path))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.body(for: evaluation)
        _ = try await send(request)
    }

    /// Nil fields go out as JSON null, so clearing an answer on the phone clears it on the server.
    nonisolated static func body(for evaluation: V1BrickEvaluation) throws -> Data {
        let payload: [String: Any] = [
            "brickGroupId": evaluation.brickGroupId,
            "rpe": evaluation.rpe ?? NSNull(),
            "transitionRating": evaluation.transitionRating ?? NSNull(),
            "feeling": evaluation.feeling ?? NSNull(),
            "notes": evaluation.notes ?? NSNull(),
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return data
        case 400, 404: throw SharpitAPIError.badRequest
        case 401: throw SharpitAPIError.unauthorized
        default: throw SharpitAPIError.server
        }
    }
}
