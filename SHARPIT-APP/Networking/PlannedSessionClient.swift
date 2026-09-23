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

nonisolated struct CreatePlannedSessionPayload: Codable, Sendable {
    let type: String
    let date: String
    let startTime: String?
    let title: String?
    let description: String?
    let durationMin: Double?
    let load: Double?
    let intensity: String?
    let goalId: String?
    let decisionId: String?

    init(
        type: String,
        date: String,
        startTime: String? = nil,
        title: String? = nil,
        description: String? = nil,
        durationMin: Double? = nil,
        load: Double? = nil,
        intensity: String? = nil,
        goalId: String? = nil,
        decisionId: String? = nil
    ) {
        self.type = type
        self.date = date
        self.startTime = startTime
        self.title = title
        self.description = description
        self.durationMin = durationMin
        self.load = load
        self.intensity = intensity
        self.goalId = goalId
        self.decisionId = decisionId
    }
}

nonisolated struct UpdatePlannedSessionPayload: Codable, Sendable {
    let type: String?
    let date: String?
    let title: String?
    let description: String?
    let durationMin: Double?
    let load: Double?
    let intensity: String?

    init(
        type: String? = nil,
        date: String? = nil,
        title: String? = nil,
        description: String? = nil,
        durationMin: Double? = nil,
        load: Double? = nil,
        intensity: String? = nil
    ) {
        self.type = type
        self.date = date
        self.title = title
        self.description = description
        self.durationMin = durationMin
        self.load = load
        self.intensity = intensity
    }
}

protocol PlannedSessionMutating: Sendable {
    func createSession(_ payload: CreatePlannedSessionPayload, token: String) async throws -> V1PlannedSessionItem
    func updateSession(id: String, patch: UpdatePlannedSessionPayload, token: String) async throws -> V1PlannedSessionItem
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

    func pushToWatch(sessionId: String, force: Bool, token: String) async throws -> PlannedSessionWatchPushResult {
        var request = URLRequest(url: baseURL.appending(path: "/api/garmin/workouts/from-planned-session"))
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

    func createSession(_ payload: CreatePlannedSessionPayload, token: String) async throws -> V1PlannedSessionItem {
        var request = URLRequest(url: baseURL.appending(path: "/api/planned-sessions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }

        return try JSONDecoder().decode(V1PlannedSessionItem.self, from: data)
    }

    func updateSession(id: String, patch: UpdatePlannedSessionPayload, token: String) async throws -> V1PlannedSessionItem {
        var request = URLRequest(url: baseURL.appending(path: "/api/planned-sessions/\(id)"))
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(patch)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }

        return try JSONDecoder().decode(V1PlannedSessionItem.self, from: data)
    }

    func deleteSession(id: String, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/planned-sessions/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
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

    var errorDescription: String? {
        switch self {
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
