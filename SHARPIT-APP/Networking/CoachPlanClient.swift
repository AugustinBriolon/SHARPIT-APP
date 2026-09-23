import Foundation

protocol CoachPlanServing: Sendable {
    func generateWeek(
        days: Int,
        goalId: String?,
        focus: String?,
        startDate: Date?,
        token: String,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> V1GeneratedPlan

    func adaptPlan(
        days: Int,
        focus: String?,
        token: String,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> V1AdaptPlanResult
}

actor CoachPlanClient: CoachPlanServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func generateWeek(
        days: Int,
        goalId: String?,
        focus: String?,
        startDate: Date? = nil,
        token: String,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> V1GeneratedPlan {
        var payload: [String: Any] = [
            "days": days
        ]
        if let goalId, !goalId.isEmpty, goalId != "none" {
            payload["goalId"] = goalId
        }
        if let focus, !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["focus"] = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            payload["startDate"] = formatter.string(from: startDate)
        }

        return try await streamCoach(
            path: "/api/coach/plan",
            payload: payload,
            token: token,
            onReasoning: onReasoning
        )
    }

    func adaptPlan(
        days: Int,
        focus: String?,
        token: String,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> V1AdaptPlanResult {
        var payload: [String: Any] = [
            "days": days
        ]
        if let focus, !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["focus"] = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return try await streamCoach(
            path: "/api/coach/adapt",
            payload: payload,
            token: token,
            onReasoning: onReasoning
        )
    }

    private func streamCoach<T: Decodable>(
        path: String,
        payload: [String: Any],
        token: String,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300 // Generation can take 30-60s
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw SharpitAPIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw SharpitAPIError.server
            }
        }

        var reasoning = ""
        var finalResult: T?

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !jsonString.isEmpty, jsonString != "[DONE]",
                  let jsonData = jsonString.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { continue }

            if let type = event["type"] as? String {
                switch type {
                case "reasoning":
                    if let delta = event["delta"] as? String {
                        reasoning += delta
                        onReasoning(reasoning)
                    }
                case "result":
                    if let value = event["value"] {
                        let valueData = try JSONSerialization.data(withJSONObject: value)
                        finalResult = try JSONDecoder().decode(T.self, from: valueData)
                    }
                case "error":
                    let message = event["message"] as? String ?? "La génération a échoué."
                    throw CoachPlanError.custom(message)
                default:
                    break
                }
            }
        }

        if let finalResult {
            return finalResult
        }
        throw CoachPlanError.custom("Aucun résultat renvoyé par le coach.")
    }
}

enum CoachPlanError: Error, LocalizedError {
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .custom(let message): message
        }
    }
}
