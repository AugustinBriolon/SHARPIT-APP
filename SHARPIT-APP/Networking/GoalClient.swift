import Foundation

nonisolated protocol GoalServing: Sendable {
    func goals(token: String) async throws -> [V1Goal]
    func createGoal(_ input: CreateGoalInput, token: String) async throws -> V1Goal
    func toggleAchieved(id: String, achieved: Bool, token: String) async throws -> V1Goal
    func deleteGoal(id: String, token: String) async throws
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

    private func validate(response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else {
            throw SharpitAPIError.server
        }
    }
}
