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
    /// One page of the history, newest first: up to `limit` sessions started before `before`
    /// (the most recent ones when nil). Activité reads the history this way, years of it included.
    func activityPage(before: Date?, limit: Int, token: String) async throws -> [V1ActivityListItem]
    /// The sessions started in `[from, to)`, either side open when nil — for a screen that reads
    /// a week or a season, never the whole history.
    func activities(from: Date?, to: Date?, token: String) async throws -> [V1ActivityListItem]
    func activity(id: String, token: String) async throws -> V1ActivityDetail
    func activityStream(id: String, token: String) async throws -> V1ActivityStreamPayload
    /// A multisport session's sport legs, each with its own recording.
    func multisportStreams(id: String, token: String) async throws -> [V1MultisportLegStream]
    /// Downsampled GPS paths for every streamed activity — one call for the Activité list cards.
    func routePreviews(token: String) async throws -> [String: [V1ActivityCoordinate]]
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
    /// Stubs page through their whole list.
    func activityPage(before: Date?, limit: Int, token: String) async throws -> [V1ActivityListItem] {
        let all = try await activities(token: token).sorted { $0.date > $1.date }
        return Array(all.filter { before == nil || $0.date < before! }.prefix(limit))
    }
    /// Stubs window their whole list.
    func activities(from: Date?, to: Date?, token: String) async throws -> [V1ActivityListItem] {
        try await activities(token: token).filter { activity in
            (from.map { activity.date >= $0 } ?? true) && (to.map { activity.date < $0 } ?? true)
        }
    }
    /// Most conformers hold no cache, so the default is to have nothing to forget.
    func invalidateActivities() async {}
    func forgetActivity(id _: String) async {}
    /// Conformers that serve no multisport session have no legs to give.
    func multisportStreams(id _: String, token _: String) async throws -> [V1MultisportLegStream] { [] }
    /// Stubs and previews have no GPS paths.
    func routePreviews(token _: String) async throws -> [String: [V1ActivityCoordinate]] { [:] }
}

actor ActivityClient: ActivityServing, ActivityMutating {
    private let session: URLSession
    private let baseURL: URL
    private var activitiesCache: [V1ActivityListItem]?
    private var detailCache: [String: V1ActivityDetail] = [:]
    private var streamCache: [String: V1ActivityStreamPayload] = [:]
    // shortcut: memory only, so each launch asks once more (the server answers from its cache); keep them on disk if the race page is opened often.
    private var multisportCache: [String: [V1MultisportLegStream]] = [:]
    private var routePreviewsCache: [String: [V1ActivityCoordinate]]?
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
        dropDetailsDisagreeing(with: activities)
        return activities
    }

    func activityPage(before: Date?, limit: Int, token: String) async throws -> [V1ActivityListItem] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            query.append(URLQueryItem(name: "before", value: Self.instant(before)))
        }
        let page: [V1ActivityListItem] = try await request(path: "/api/v1/activities", queryItems: query, token: token)
        dropDetailsDisagreeing(with: page)
        return page
    }

    func activities(from: Date?, to: Date?, token: String) async throws -> [V1ActivityListItem] {
        var query: [URLQueryItem] = []
        if let from { query.append(URLQueryItem(name: "after", value: Self.instant(from))) }
        if let to { query.append(URLQueryItem(name: "before", value: Self.instant(to))) }
        return try await request(path: "/api/v1/activities", queryItems: query, token: token)
    }

    /// An instant as the server reads it, to the millisecond.
    private nonisolated static func instant(_ date: Date) -> String {
        date.ISO8601Format(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    /// How many recent sessions have their disk copy checked on each list read; older ones are
    /// rarely edited, and each check decodes a file.
    private nonisolated static let diskAgreementWindow = 40

    /// Forgets every kept detail the fresh list contradicts, so the page never opens on an old
    /// title the list has already replaced.
    private func dropDetailsDisagreeing(with items: [V1ActivityListItem]) {
        let recent = Set(items.sorted { $0.date > $1.date }.prefix(Self.diskAgreementWindow).map(\.id))
        for item in items {
            let kept = detailCache[item.id] ?? (recent.contains(item.id) ? storedDetail(id: item.id) : nil)
            guard let kept, !ActivityCachePolicy.detail(kept, agreesWith: item) else { continue }
            detailCache[item.id] = nil
            disk?.remove(.detail, id: item.id)
        }
    }

    private func storedDetail(id: String) -> V1ActivityDetail? {
        disk?.read(.detail, id: id).flatMap { try? JSONDecoder().decode(V1ActivityDetail.self, from: $0.data) }
    }

    /// Memory, then disk while the copy is fresh, then the server — and the disk copy of any age
    /// when the server cannot answer, so a session opens offline.
    func activity(id: String, token: String) async throws -> V1ActivityDetail {
        // A copy still waiting for its compliance reading is asked again, or the page would
        // say « Calcul en cours » until the copy expired.
        if let cached = detailCache[id], cached.plannedSession?.awaitsAnalysis != true {
            return cached
        }
        let stored = disk?.read(.detail, id: id)
        if let stored, ActivityCachePolicy.isFresh(.detail, savedAt: stored.savedAt),
           let detail = try? JSONDecoder().decode(V1ActivityDetail.self, from: stored.data),
           detail.plannedSession?.awaitsAnalysis != true {
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
        // A heart-rate-only copy kept by an earlier build is asked again too.
        if let stored = disk?.read(.stream, id: id),
           let stream = try? JSONDecoder().decode(V1ActivityStreamPayload.self, from: stored.data),
           stream.isComplete {
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

    func multisportStreams(id: String, token: String) async throws -> [V1MultisportLegStream] {
        if let cached = multisportCache[id] {
            return cached
        }
        let streams: V1MultisportStreams = try await request(
            path: "/api/v1/activities/\(id)/multisport-streams",
            queryItems: [],
            token: token
        )
        multisportCache[id] = streams.legs
        return streams.legs
    }

    func routePreviews(token: String) async throws -> [String: [V1ActivityCoordinate]] {
        if let routePreviewsCache { return routePreviewsCache }
        let raw: [String: [[Double]]] = try await request(
            path: "/api/activities/route-previews",
            queryItems: [],
            token: token
        )
        let mapped = raw.mapValues { pairs in
            pairs.compactMap { pair -> V1ActivityCoordinate? in
                guard pair.count >= 2 else { return nil }
                return V1ActivityCoordinate(latitude: pair[0], longitude: pair[1])
            }
        }.filter { $0.value.count >= 2 }
        routePreviewsCache = mapped
        return mapped
    }

    func invalidateActivities() {
        activitiesCache = nil
        routePreviewsCache = nil
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
