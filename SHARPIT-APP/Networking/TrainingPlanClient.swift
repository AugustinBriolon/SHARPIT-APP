import Foundation

protocol TrainingPlanServing: Sendable {
    func fetchActivePlan(token: String) async throws -> V1TrainingPlan?
    func generatePlan(goalId: String, token: String) async throws -> V1TrainingPlan
    func archivePlan(id: String, token: String) async throws
}

actor TrainingPlanClient: TrainingPlanServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchActivePlan(token: String) async throws -> V1TrainingPlan? {
        let request = makeRequest(path: "/api/v1/training-plans", method: "GET", token: token)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }

        // The endpoint returns null when there is no active plan
        if data.isEmpty || String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
            return nil
        }
        return try JSONDecoder().decode(V1TrainingPlan.self, from: data)
    }

    func generatePlan(goalId: String, token: String) async throws -> V1TrainingPlan {
        var request = makeRequest(path: "/api/v1/training-plans", method: "POST", token: token)
        let payload = ["goalId": goalId]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else {
            if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = decoded["error"] as? String {
                throw TrainingPlanError.custom(message)
            }
            throw SharpitAPIError.server
        }
        return try JSONDecoder().decode(V1TrainingPlan.self, from: data)
    }

    func archivePlan(id: String, token: String) async throws {
        let request = makeRequest(path: "/api/v1/training-plans/\(id)", method: "DELETE", token: token)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else {
            if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = decoded["error"] as? String {
                throw TrainingPlanError.custom(message)
            }
            throw SharpitAPIError.server
        }
    }

    private func makeRequest(path: String, method: String, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

enum TrainingPlanError: Error, LocalizedError {
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .custom(let message): message
        }
    }
}
