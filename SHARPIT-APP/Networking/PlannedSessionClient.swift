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
    /// Asks the coach to read the session against its activity again. The server answers at
    /// once and writes the analysis behind (ADR-036); the page reads it back.
    func reanalyze(sessionId: String, token: String) async throws
}

extension PlannedSessionLinking {
    func reanalyze(sessionId _: String, token _: String) async throws {
        throw SharpitAPIError.server
    }
}

/// Writes the athlete makes to their own plan. A refusal comes back as
/// `SharpitAPIError.message` carrying the server's words, so a form can say what to fix.
protocol PlannedSessionMutating: Sendable {
    func createSession(_ fields: PlannedSessionFields, token: String) async throws -> V1PlannedSessionItem
    func updateSession(id: String, fields: PlannedSessionFields, token: String) async throws -> V1PlannedSessionItem
    func deleteSession(id: String, token: String) async throws
}

actor PlannedSessionClient: PlannedSessionServing, PlannedSessionLinking, PlannedSessionMutating {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func plannedSessions(from: Date, to: Date, token: String) async throws -> [V1PlannedSessionItem] {
        guard var components = URLComponents(
            url: baseURL.appending(path: "/api/v1/planned-sessions"),
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
        request.cachePolicy = .reloadIgnoringLocalCacheData
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
            try SharpitHTTPStatus.throwIfUnauthorized(status)
            throw SharpitAPIError.server
        }
        do {
            return try JSONDecoder().decode([V1PlannedSessionItem].self, from: data)
        } catch {
            throw PlannedSessionClientError.decoding(String(describing: error))
        }
    }

    func link(sessionId: String, activityId: String?, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/planned-sessions/\(sessionId)/link"))
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
        case 401, 403: throw SharpitAPIError.unauthorized
        default: throw SharpitAPIError.server
        }
    }

    /// Exposed for tests: GET list status mapping.
    nonisolated static func mapListStatus(_ status: Int) throws {
        guard status == 200 else {
            try SharpitHTTPStatus.throwIfUnauthorized(status)
            throw SharpitAPIError.server
        }
    }

    func createSession(_ fields: PlannedSessionFields, token: String) async throws -> V1PlannedSessionItem {
        let data = try await write(path: "/api/v1/planned-sessions", method: "POST", fields: fields, token: token)
        return try decodeSession(data)
    }

    func updateSession(id: String, fields: PlannedSessionFields, token: String) async throws -> V1PlannedSessionItem {
        let data = try await write(path: "/api/v1/planned-sessions/\(id)", method: "PATCH", fields: fields, token: token)
        return try decodeSession(data)
    }

    func deleteSession(id: String, token: String) async throws {
        _ = try await write(path: "/api/v1/planned-sessions/\(id)", method: "DELETE", fields: nil, token: token)
    }

    func reanalyze(sessionId: String, token: String) async throws {
        _ = try await write(path: "/api/v1/planned-sessions/\(sessionId)/analyze", method: "POST", fields: nil, token: token)
    }

    private func write(path: String, method: String, fields: PlannedSessionFields?, token: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let fields {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(fields)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200...299: return data
        case 401, 403: throw SharpitAPIError.unauthorized
        case 429: throw SharpitAPIError.rateLimited
        case 400...499: throw Self.refusal(in: data).map(SharpitAPIError.message) ?? SharpitAPIError.badRequest
        default: throw SharpitAPIError.server
        }
    }

    private func decodeSession(_ data: Data) throws -> V1PlannedSessionItem {
        do {
            return try JSONDecoder().decode(V1PlannedSessionItem.self, from: data)
        } catch {
            throw PlannedSessionClientError.decoding(String(describing: error))
        }
    }

    /// What the server said it refused. A Zod refusal reads « Données invalides » with the
    /// field's own message in `details` — « Le déroulé de la séance est requis » — and the
    /// field's message is the one worth showing.
    nonisolated static func refusal(in data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        let details = body["details"]
        let fieldMessages: [String] = {
            guard case .object(let fields)? = details?["fieldErrors"] else { return [] }
            return fields.keys.sorted().compactMap { fields[$0]?.array?.first?.string }
        }()
        let formMessages = details?["formErrors"]?.array?.compactMap(\.string) ?? []
        let message = fieldMessages.first ?? formMessages.first ?? body["error"]?.string
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return nil
        }
        return message
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
