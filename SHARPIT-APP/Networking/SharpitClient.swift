import Foundation

/// The client for the canonical `/api/v1` contract (ADR-040). Each resource has its own
/// protocol so a screen and its tests depend only on what they read.
nonisolated protocol SleepServing: Sendable {
    func sleep(trainingDayId: String, token: String) async throws -> V1SleepResponse
}

nonisolated protocol RecoveryServing: Sendable {
    func recovery(trainingDayId: String, token: String) async throws -> V1RecoveryResponse
}

/// Asks the server to pull the athlete's providers, and when it last did.
nonisolated protocol SyncServing: Sendable {
    func syncStatus(token: String) async throws -> V1SyncStatus
    func sync(token: String) async throws -> V1SyncStatus
}

/// Sends day summaries read from Apple Health; the server fills only what no provider wrote.
nonisolated protocol HealthUploadServing: Sendable {
    func uploadHealth(_ days: [HealthDailySummary], token: String) async throws -> Int
}

actor SharpitClient: TodayServing, SleepServing, RecoveryServing, SyncServing, HealthUploadServing {
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

    func syncStatus(token: String) async throws -> V1SyncStatus {
        try await send(V1SyncStatus.self, path: "/api/v1/sync-status", method: "GET", token: token)
    }

    /// A sync pulls every provider and can take a minute or more; the default 60 s timeout
    /// would give up on a request the server is still honouring.
    func sync(token: String) async throws -> V1SyncStatus {
        try await send(V1SyncStatus.self, path: "/api/v1/sync", method: "POST", token: token, timeout: 240)
    }

    func uploadHealth(_ days: [HealthDailySummary], token: String) async throws -> Int {
        let body = try JSONEncoder().encode(HealthUpload(source: "apple-health", days: days))
        return try await send(
            HealthUploadResult.self,
            path: "/api/v1/health-samples",
            method: "POST",
            token: token,
            body: body
        ).updatedDays
    }

    /// Every v1 read so far is one training day of one resource.
    private func day<Payload: Decodable>(
        _ type: Payload.Type,
        path: String,
        trainingDayId: String,
        token: String
    ) async throws -> Payload {
        try await send(
            type,
            path: path,
            method: "GET",
            query: [URLQueryItem(name: "trainingDayId", value: trainingDayId)],
            token: token
        )
    }

    private func send<Payload: Decodable>(
        _: Payload.Type,
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        token: String,
        timeout: TimeInterval = 60,
        body: Data? = nil
    ) async throws -> Payload {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw SharpitAPIError.server }

        var request = URLRequest(url: url, timeoutInterval: timeout)
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
        case 200:
            break
        case 400:
            throw SharpitAPIError.badRequest
        case 401, 403:
            throw SharpitAPIError.unauthorized
        case 429:
            throw SharpitAPIError.rateLimited
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

private nonisolated struct HealthUpload: Encodable {
    let source: String
    let days: [HealthDailySummary]
}

private nonisolated struct HealthUploadResult: Decodable {
    let updatedDays: Int
}
