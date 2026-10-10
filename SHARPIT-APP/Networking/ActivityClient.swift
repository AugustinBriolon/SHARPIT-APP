import Foundation

enum ActivityClientError: Error, Equatable, LocalizedError {
    case invalidResponse(status: Int, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let status, let body):
            return "API \(status) — \(body)"
        case .decoding(let message):
            return "Réponse API incompatible — \(message)"
        }
    }
}

protocol ActivityServing: Sendable {
    func activities(token: String) async throws -> [V1ActivityListItem]
    func activities(forceRefresh: Bool, token: String) async throws -> [V1ActivityListItem]
    func activity(id: String, token: String) async throws -> V1ActivityDetail
    func activityStream(id: String, token: String) async throws -> V1ActivityStreamPayload
    func generateNarrative(id: String, token: String) async throws -> V1ActivityDetail
    func updateSubjective(id: String, rpe: Double?, feeling: String?, token: String) async throws
    /// Forgets the cached list. Linking a session changes what each activity says about its
    /// plan, and a list read afterwards must not repeat the old answer.
    func invalidateActivities() async
    /// Forgets one activity's stored detail, once a change made elsewhere — a session delinked —
    /// rewrote what it says.
    func forgetActivity(id: String) async
}

/// Logging, editing and deleting a done session (`/api/v1/activities`, SHARPIT ADR-040).
protocol ActivityMutating: Sendable {
    /// The new activity's id.
    func createActivity(_ fields: [String: JSONValue], token: String) async throws -> String
    /// Only the fields named: an absent key leaves a field, `null` clears it.
    func updateActivity(id: String, fields: [String: JSONValue], token: String) async throws
    func deleteActivity(id: String, token: String) async throws
    /// Sends a strength session to the Garmin watch as a workout to do again, scheduled today;
    /// returns what to tell the athlete. Refusals (no Garmin, below Pro) carry the server's words.
    func pushActivityToWatch(id: String, token: String) async throws -> String
}

extension ActivityServing {
    func activities(forceRefresh: Bool, token: String) async throws -> [V1ActivityListItem] {
        try await activities(token: token)
    }
    /// Most conformers hold no cache, so the default is to have nothing to forget.
    func invalidateActivities() async {}
    func forgetActivity(id _: String) async {}
}

actor ActivityClient: ActivityServing, ActivityMutating {
    private let session: URLSession
    private let baseURL: URL
    private var activitiesCache: [V1ActivityListItem]?
    private var detailCache: [String: V1ActivityDetail] = [:]
    private var streamCache: [String: V1ActivityStreamPayload] = [:]
    /// Survives the client and the launch: a session opened once opens instantly after.
    private let disk: ActivityDiskCache?

    init(
        session: URLSession = .shared,
        baseURL: URL = APIConfiguration.baseURL,
        disk: ActivityDiskCache? = .shared
    ) {
        self.session = session
        self.baseURL = baseURL
        self.disk = disk
    }

    func activities(token: String) async throws -> [V1ActivityListItem] {
        try await activities(forceRefresh: false, token: token)
    }

    func activities(forceRefresh: Bool, token: String) async throws -> [V1ActivityListItem] {
        if !forceRefresh, let activitiesCache {
            return activitiesCache
        }
        let activities: [V1ActivityListItem] = try await request(
            path: "/api/v1/activities",
            queryItems: [],
            token: token
        )
        activitiesCache = activities
        return activities
    }

    /// Memory, then disk while the copy is fresh, then the server — and the disk copy of any age
    /// when the server cannot answer, so a session opens offline.
    func activity(id: String, token: String) async throws -> V1ActivityDetail {
        if let cached = detailCache[id] {
            return cached
        }
        let stored = disk?.read(.detail, id: id)
        if let stored, ActivityCachePolicy.isFresh(.detail, savedAt: stored.savedAt),
           let detail = try? JSONDecoder().decode(V1ActivityDetail.self, from: stored.data) {
            detailCache[id] = detail
            return detail
        }
        do {
            let data = try await fetch(path: "/api/v1/activities/\(id)", queryItems: [], token: token)
            let detail: V1ActivityDetail = try decode(data)
            detailCache[id] = detail
            disk?.write(data, .detail, id: id)
            return detail
        } catch {
            if let stored, let detail = try? JSONDecoder().decode(V1ActivityDetail.self, from: stored.data) {
                detailCache[id] = detail
                return detail
            }
            throw error
        }
    }

    /// A recorded session's samples never change, so an available stream is read once.
    func activityStream(id: String, token: String) async throws -> V1ActivityStreamPayload {
        if let cached = streamCache[id] {
            return cached
        }
        if let stored = disk?.read(.stream, id: id),
           let stream = try? JSONDecoder().decode(V1ActivityStreamPayload.self, from: stored.data) {
            streamCache[id] = stream
            return stream
        }
        let data = try await fetch(path: "/api/v1/activities/\(id)/streams", queryItems: [], token: token)
        let stream: V1ActivityStreamPayload = try decode(data)
        streamCache[id] = stream
        // Not yet backfilled, or heart rate alone while a fuller recording may still come:
        // kept out of the disk so the next opening asks again.
        if stream.available && stream.isComplete {
            disk?.write(data, .stream, id: id)
        }
        return stream
    }

    func invalidateActivities() {
        activitiesCache = nil
    }

    func forgetActivity(id: String) {
        dropDetail(id: id)
    }

    /// Named apart from `forgetActivity`: inside the actor that call resolves to the protocol's
    /// main-actor default instead of this method.
    private func dropDetail(id: String) {
        detailCache[id] = nil
        disk?.remove(.detail, id: id)
        activitiesCache = nil
    }

    /// The analysis rewrites the detail; the new one replaces the stored copy.
    func generateNarrative(id: String, token: String) async throws -> V1ActivityDetail {
        let data = try await fetch(
            path: "/api/v1/activities/\(id)/narrative",
            method: "POST",
            body: Data(#"{"wait":true}"#.utf8),
            queryItems: [],
            token: token
        )
        let detail: V1ActivityDetail = try decode(data)
        detailCache[id] = detail
        disk?.write(data, .detail, id: id)
        return detail
    }

    func updateSubjective(id: String, rpe: Double?, feeling: String?, token: String) async throws {
        var payload: [String: Any] = [:]
        payload["rpe"] = rpe ?? NSNull()
        payload["feeling"] = feeling ?? NSNull()
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await requestData(path: "/api/v1/activities/\(id)", body: body, token: token)
        detailCache[id] = nil
        disk?.remove(.detail, id: id)
        activitiesCache = nil
    }

    private struct CreatedActivity: Decodable { let id: String }

    func createActivity(_ fields: [String: JSONValue], token: String) async throws -> String {
        let data = try await write(path: "/api/v1/activities", method: "POST", body: JSONEncoder().encode(fields), token: token)
        activitiesCache = nil
        return try JSONDecoder().decode(CreatedActivity.self, from: data).id
    }

    func updateActivity(id: String, fields: [String: JSONValue], token: String) async throws {
        _ = try await write(path: "/api/v1/activities/\(id)", method: "PATCH", body: JSONEncoder().encode(fields), token: token)
        dropDetail(id: id)
    }

    func deleteActivity(id: String, token: String) async throws {
        _ = try await write(path: "/api/v1/activities/\(id)", method: "DELETE", body: nil, token: token)
        dropDetail(id: id)
        disk?.remove(.stream, id: id)
        streamCache[id] = nil
        activitiesCache = nil
    }

    func pushActivityToWatch(id: String, token: String) async throws -> String {
        let body = try JSONEncoder().encode(["activityId": JSONValue.string(id), "schedule": .bool(true)])
        _ = try await write(path: "/api/v1/garmin/workouts/from-activity", method: "POST", body: body, token: token)
        return "La séance est sur ta montre Garmin, prévue aujourd’hui."

    }

    /// A write: a refusal carries the server's own field message, a 5xx is `.server` so
    /// `SharpitRetry` tries it again.
    private func write(path: String, method: String, body: Data?, token: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bear" + "er " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
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
        case 200...299: return data
        case 401: throw SharpitAPIError.unauthorized
        case 403 where PlannedSessionClient.refusal(in: data) == "pro_required":
            throw SharpitAPIError.message("Envoyer une séance à la montre est réservé à SharpIt Pro.")
        case 403: throw SharpitAPIError.unauthorized
        case 429: throw SharpitAPIError.rateLimited
        case 400...499: throw PlannedSessionClient.refusal(in: data).map(SharpitAPIError.message) ?? SharpitAPIError.badRequest
        default: throw SharpitAPIError.server
        }
    }

    private func requestData(path: String, body: Data, token: String) async throws {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw SharpitAPIError.server
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = body
        request.setValue("Bear" + "er " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return }
        try SharpitHTTPStatus.throwIfUnauthorized(status)
        throw ActivityClientError.invalidResponse(status: status, body: "Mise à jour impossible")
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem],
        token: String
    ) async throws -> T {
        try decode(try await fetch(path: path, method: method, body: body, queryItems: queryItems, token: token))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ActivityClientError.decoding(String(describing: error))
        }
    }

    /// The raw answer, so the disk cache stores exactly what the server sent.
    private func fetch(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem],
        token: String
    ) async throws -> Data {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw SharpitAPIError.server
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = body
        request.setValue("Bear" + "er " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        try Self.mapReadStatus(status, body: data)
        return data
    }

    /// Exposed for tests: GET/PATCH status mapping shared with `fetch` / `requestData`.
    nonisolated static func mapReadStatus(_ status: Int, body: Data = Data()) throws {
        switch status {
        case 200, 201, 204:
            return
        case 401, 403:
            throw SharpitAPIError.unauthorized
        default:
            let text = String(data: body, encoding: .utf8) ?? "Réponse illisible"
            throw ActivityClientError.invalidResponse(status: status, body: String(text.prefix(180)))
        }
    }
}
