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

nonisolated struct PlannedSessionWatchPushResult: Sendable, Equatable {
    let workoutId: String?
    let workoutName: String?
    let scheduledDate: String?
    let pushedAt: Date?
    let alreadyPushed: Bool

    init(
        workoutId: String? = nil,
        workoutName: String? = nil,
        scheduledDate: String? = nil,
        pushedAt: Date? = nil,
        alreadyPushed: Bool = false
    ) {
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.scheduledDate = scheduledDate
        self.pushedAt = pushedAt
        self.alreadyPushed = alreadyPushed
    }
}

protocol PlannedSessionWatchPushing: Sendable {
    func pushToWatch(sessionId: String, force: Bool, token: String) async throws -> PlannedSessionWatchPushResult
}

/// Writes the athlete makes to their own plan. A refusal comes back as
/// `SharpitAPIError.message` carrying the server's words, so a form can say what to fix.
protocol PlannedSessionMutating: Sendable {
    func createSession(_ fields: PlannedSessionFields, token: String) async throws -> V1PlannedSessionItem
    func updateSession(id: String, fields: PlannedSessionFields, token: String) async throws -> V1PlannedSessionItem
    func deleteSession(id: String, token: String) async throws
}

actor PlannedSessionClient: PlannedSessionServing, PlannedSessionLinking, PlannedSessionWatchPushing, PlannedSessionMutating {
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
        case 401: throw SharpitAPIError.unauthorized
        default: throw SharpitAPIError.server
        }
    }

    func pushToWatch(sessionId: String, force: Bool, token: String) async throws -> PlannedSessionWatchPushResult {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/garmin/workouts/from-planned-session"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "plannedSessionId": sessionId,
            "schedule": true,
            "force": force
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let workoutId: String?
            if let strId = decoded?["workoutId"] as? String {
                workoutId = strId
            } else if let numId = decoded?["workoutId"] as? NSNumber {
                workoutId = numId.stringValue
            } else {
                workoutId = nil
            }
            let workoutName = decoded?["workoutName"] as? String
            let scheduledDate = decoded?["scheduledDate"] as? String
            let pushedAtStr = decoded?["pushedAt"] as? String
            let pushedAt: Date
            if let pushedAtStr {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let standard = ISO8601DateFormatter()
                pushedAt = formatter.date(from: pushedAtStr) ?? standard.date(from: pushedAtStr) ?? Date()
            } else {
                pushedAt = Date()
            }

            return PlannedSessionWatchPushResult(
                workoutId: workoutId,
                workoutName: workoutName,
                scheduledDate: scheduledDate,
                pushedAt: pushedAt,
                alreadyPushed: false
            )

        case 401:
            throw SharpitAPIError.unauthorized

        case 403:
            throw PlannedSessionWatchPushError.proRequired

        case 409:
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = decoded?["error"] as? String ?? "Cette séance est déjà sur la montre Garmin."
            let receipt = decoded?["receipt"] as? [String: Any]
            let scheduledDate = receipt?["scheduledDate"] as? String ?? decoded?["scheduledDate"] as? String
            throw PlannedSessionWatchPushError.alreadyPushed(message: message, scheduledDate: scheduledDate)

        case 404:
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = decoded?["error"] as? String ?? "Compte Garmin non connecté."
            throw PlannedSessionWatchPushError.notConnected(message)

        case 400:
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = decoded?["error"] as? String ?? "Séance non supportée pour l'envoi."
            throw PlannedSessionWatchPushError.unsupported(message)

        default:
            if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = decoded["error"] as? String {
                throw PlannedSessionWatchPushError.failed(message)
            }
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

nonisolated enum PlannedSessionWatchPushError: Error, LocalizedError, Equatable {
    case alreadyPushed(message: String, scheduledDate: String?)
    case notConnected(String)
    case unsupported(String)
    case failed(String)
    /// Below SharpIt Pro: sending to the watch is what SHARPIT adds.
    case proRequired

    var errorDescription: String? {
        switch self {
        case .proRequired: "L'envoi vers la montre est réservé à SharpIt Pro."
        case .alreadyPushed(let message, _): message
        case .notConnected(let message): message
        case .unsupported(let message): message
        case .failed(let message): message
        }
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
