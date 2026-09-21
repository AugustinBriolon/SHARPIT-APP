import Foundation

/// The client for the canonical `/api/v1` contract (ADR-040). Each resource has its own
/// protocol so a screen and its tests depend only on what they read.
nonisolated protocol SleepServing: Sendable {
    func sleep(trainingDayId: String, token: String) async throws -> V1SleepResponse
}

nonisolated protocol RecoveryServing: Sendable {
    func recovery(trainingDayId: String, token: String) async throws -> V1RecoveryResponse
}

actor SharpitClient: TodayServing, SleepServing, RecoveryServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse {
        try await day(V1TodayResponse.self, path: "/api/v1/today", trainingDayId: trainingDayId, token: token)
    }

    func sleep(trainingDayId: String, token: String) async throws -> V1SleepResponse {
        try await day(V1SleepResponse.self, path: "/api/v1/sleep", trainingDayId: trainingDayId, token: token)
    }

    func recovery(trainingDayId: String, token: String) async throws -> V1RecoveryResponse {
        try await day(V1RecoveryResponse.self, path: "/api/v1/recovery", trainingDayId: trainingDayId, token: token)
    }

    /// Every v1 read so far is one training day of one resource.
    private func day<Payload: Decodable>(
        _: Payload.Type,
        path: String,
        trainingDayId: String,
        token: String
    ) async throws -> Payload {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        components.queryItems = [URLQueryItem(name: "trainingDayId", value: trainingDayId)]
        guard let url = components.url else { throw SharpitAPIError.server }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            break
        case 400:
            throw SharpitAPIError.badRequest
        case 401:
            throw SharpitAPIError.unauthorized
        default:
            throw SharpitAPIError.server
        }

        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw SharpitAPIError.server
        }
    }
}
