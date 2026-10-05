import Foundation

nonisolated protocol GoalServing: Sendable {
    func goals(token: String) async throws -> [V1Goal]
    func createGoal(_ input: CreateGoalInput, token: String) async throws -> V1Goal
    func toggleAchieved(id: String, achieved: Bool, token: String) async throws -> V1Goal
    func deleteGoal(id: String, token: String) async throws
    /// Only the fields named (`GoalDraft.changes(from:)`): an absent key leaves a field, `null` clears it.
    func updateGoal(id: String, fields: [String: JSONValue], token: String) async throws -> V1Goal
}

extension GoalServing {
    func updateGoal(id _: String, fields _: [String: JSONValue], token _: String) async throws -> V1Goal {
        throw SharpitAPIError.server
    }
}

actor GoalClient: GoalServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func goals(token: String) async throws -> [V1Goal] {
        let request = makeRequest(path: "/api/v1/goals", method: "GET", token: token)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode([V1Goal].self, from: data)
    }

    func createGoal(_ input: CreateGoalInput, token: String) async throws -> V1Goal {
        var request = makeRequest(path: "/api/v1/goals", method: "POST", token: token)
        request.httpBody = try JSONEncoder().encode(input)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(V1Goal.self, from: data)
    }

    func toggleAchieved(id: String, achieved: Bool, token: String) async throws -> V1Goal {
        var request = makeRequest(path: "/api/v1/goals/\(id)", method: "PATCH", token: token)
        let body = ["achieved": achieved]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(V1Goal.self, from: data)
    }

    func updateGoal(id: String, fields: [String: JSONValue], token: String) async throws -> V1Goal {
        var request = makeRequest(path: "/api/v1/goals/\(id)", method: "PATCH", token: token)
        request.httpBody = try JSONEncoder().encode(fields)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(V1Goal.self, from: data)
    }

    func deleteGoal(id: String, token: String) async throws {
        let request = makeRequest(path: "/api/v1/goals/\(id)", method: "DELETE", token: token)
        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func makeRequest(path: String, method: String, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// A refusal carries the server's own field message (« Une course doit avoir une date »).
    private func validate(response: URLResponse, data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200...299: return
        case 401, 403: throw SharpitAPIError.unauthorized
        case 429: throw SharpitAPIError.rateLimited
        case 400...499: throw PlannedSessionClient.refusal(in: data).map(SharpitAPIError.message) ?? SharpitAPIError.badRequest
        default: throw SharpitAPIError.server
        }
    }

    private func validate(response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else {
            throw SharpitAPIError.server
        }
    }
}
