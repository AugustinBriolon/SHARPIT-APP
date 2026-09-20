import Foundation

protocol PlannedSessionServing: Sendable {
    func plannedSessions(from: Date, to: Date, token: String) async throws -> [V1PlannedSessionItem]
}

/// Pairs a prescription with the activity that carried it out, or unpairs it.
///
/// A protocol of its own, not a method on `PlannedSessionServing`: reading the plan and
/// changing what it is linked to are different needs, and a screen that only reads should
/// not have to stub a write.
protocol PlannedSessionLinking: Sendable {
    /// `activityId: nil` removes the link.
    func link(sessionId: String, activityId: String?, token: String) async throws
}

actor PlannedSessionClient: PlannedSessionServing, PlannedSessionLinking {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func plannedSessions(from: Date, to: Date, token: String) async throws -> [V1PlannedSessionItem] {
        guard var components = URLComponents(
            url: baseURL.appending(path: "/api/planned-sessions"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        components.queryItems = [
            URLQueryItem(name: "from", value: Self.dayString(from)),
            URLQueryItem(name: "to", value: Self.dayString(to))
        ]
        guard let url = components.url else { throw SharpitAPIError.server }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bear" + "er " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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
            return try JSONDecoder().decode([V1PlannedSessionItem].self, from: data)
        } catch {
            throw PlannedSessionClientError.decoding(String(describing: error))
        }
    }

    func link(sessionId: String, activityId: String?, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/planned-sessions/\(sessionId)/link"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["activityId": activityId.map { $0 as Any } ?? NSNull()]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return
        case 401: throw SharpitAPIError.unauthorized
        default: throw SharpitAPIError.server
        }
    }

    private nonisolated static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum PlannedSessionClientError: Error, LocalizedError {
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .decoding: "Réponse du plan incompatible"
        }
    }
}
