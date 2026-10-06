import Foundation

/// One stage of a multi-day hike — an activity of type HIKE, as `/api/v1/hike-trips` selects it
/// (`hikeTripActivitySelect`): its date, time, load, the place it was recorded and its hike metrics.
nonisolated struct V1HikeTripMember: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let type: V1ActivityType
    let date: Date
    let title: String?
    /// Seconds.
    let duration: Double?
    let load: Double?
    let observedLocationLabel: String?
    let distanceM: Double?
    let elevationM: Double?
    let elevationLossM: Double?

    private enum CodingKeys: String, CodingKey {
        case id, type, date, title, duration, load, observedLocationLabel, hikeMetrics
    }

    private nonisolated struct Metrics: Decodable {
        let distanceM: Double?
        let elevationM: Double?
        let elevationLossM: Double?
    }

    init(
        id: String,
        type: V1ActivityType = .hike,
        date: Date,
        title: String? = nil,
        duration: Double? = nil,
        load: Double? = nil,
        observedLocationLabel: String? = nil,
        distanceM: Double? = nil,
        elevationM: Double? = nil,
        elevationLossM: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.date = date
        self.title = title
        self.duration = duration
        self.load = load
        self.observedLocationLabel = observedLocationLabel
        self.distanceM = distanceM
        self.elevationM = elevationM
        self.elevationLossM = elevationLossM
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = (try? container.decodeIfPresent(V1ActivityType.self, forKey: .type)) ?? .hike
        date = try Date.fromAPI(container.decode(String.self, forKey: .date))
        title = try container.decodeIfPresent(String.self, forKey: .title)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        load = try container.decodeIfPresent(Double.self, forKey: .load)
        observedLocationLabel = try container.decodeIfPresent(String.self, forKey: .observedLocationLabel)
        let metrics = try? container.decodeIfPresent(Metrics.self, forKey: .hikeMetrics)
        distanceM = metrics?.distanceM
        elevationM = metrics?.elevationM
        elevationLossM = metrics?.elevationLossM
    }

    /// The stage's name: its own title, else the sport.
    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Randonnée" : trimmed
    }
}

/// A séjour: realised hikes of several days gathered under one name (the web's `HikeTrip`).
/// Planned travel is not here — it lives in the coach's memory.
nonisolated struct V1HikeTrip: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    var name: String
    /// The stages, oldest first, as the server orders them.
    var activities: [V1HikeTripMember]
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, name, activities, updatedAt
    }

    init(id: String, name: String, activities: [V1HikeTripMember], updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.activities = activities
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        activities = (try container.decodeIfPresent([V1HikeTripMember].self, forKey: .activities) ?? [])
            .sorted { $0.date < $1.date }
        if let raw = try? container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = try? Date.fromAPI(raw)
        } else {
            updatedAt = nil
        }
    }

    /// The trip's totals, as the web's `buildHikeTripSummary` makes them.
    var summary: HikeTripSummary { HikeTripSummary(members: activities) }
}

/// The totals of a séjour — the web's `buildHikeTripSummary`, computed here from the stages so
/// the list, the detail and an edit shown on the tap read the same figures. A sum stays nil
/// when no stage carries the measure, never a zero made up.
nonisolated struct HikeTripSummary: Equatable, Sendable {
    let memberCount: Int
    let startAt: Date?
    let endAt: Date?
    let durationSec: Double?
    let distanceM: Double?
    let elevationM: Double?
    let elevationLossM: Double?
    let load: Double?
    /// The places the stages were recorded in, in walking order, each once.
    let locationLabels: [String]

    init(members: [V1HikeTripMember]) {
        let ordered = members.sorted { $0.date < $1.date }
        memberCount = ordered.count
        startAt = ordered.first?.date
        endAt = ordered.map { member -> Date in
            guard let duration = member.duration, duration > 0 else { return member.date }
            return member.date.addingTimeInterval(duration)
        }.max()
        durationSec = Self.sum(ordered.map(\.duration))
        distanceM = Self.sum(ordered.map(\.distanceM))
        elevationM = Self.sum(ordered.map(\.elevationM))
        elevationLossM = Self.sum(ordered.map(\.elevationLossM))
        load = Self.sum(ordered.map(\.load))
        var labels: [String] = []
        for member in ordered {
            let label = member.observedLocationLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !label.isEmpty, !labels.contains(label) { labels.append(label) }
        }
        locationLabels = labels
    }

    private static func sum(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }.filter(\.isFinite)
        return present.isEmpty ? nil : present.reduce(0, +)
    }
}

/// One change to a séjour: an absent field leaves it, as the web's `patchHikeTripSchema` reads it.
nonisolated struct HikeTripPatch: Equatable, Sendable {
    var name: String?
    var addActivityIds: [String] = []
    var removeActivityIds: [String] = []

    var isEmpty: Bool {
        (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && addActivityIds.isEmpty && removeActivityIds.isEmpty
    }

    var body: [String: Any] {
        var body: [String: Any] = [:]
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { body["name"] = name }
        if !addActivityIds.isEmpty { body["addActivityIds"] = addActivityIds }
        if !removeActivityIds.isEmpty { body["removeActivityIds"] = removeActivityIds }
        return body
    }
}

nonisolated protocol HikeTripServing: Sendable {
    func hikeTrips(token: String) async throws -> [V1HikeTrip]
    func createHikeTrip(name: String, activityIds: [String], token: String) async throws -> V1HikeTrip
    func updateHikeTrip(id: String, patch: HikeTripPatch, token: String) async throws -> V1HikeTrip
    func deleteHikeTrip(id: String, token: String) async throws
}

/// `/api/v1/hike-trips` and `/api/v1/hike-trips/[id]` — the web's handlers (ADR-040). A refusal
/// carries the server's French reason (`error`): a hike already in another séjour (409), the last
/// stage removed, fewer than two hikes.
actor HikeTripClient: HikeTripServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func hikeTrips(token: String) async throws -> [V1HikeTrip] {
        let data = try await send(path: "/api/v1/hike-trips", method: "GET", token: token)
        return try decode([V1HikeTrip].self, from: data)
    }

    func createHikeTrip(name: String, activityIds: [String], token: String) async throws -> V1HikeTrip {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "activityIds": activityIds,
        ] as [String: Any])
        let data = try await send(path: "/api/v1/hike-trips", method: "POST", token: token, body: body)
        return try decode(V1HikeTrip.self, from: data)
    }

    func updateHikeTrip(id: String, patch: HikeTripPatch, token: String) async throws -> V1HikeTrip {
        let body = try JSONSerialization.data(withJSONObject: patch.body)
        let data = try await send(path: "/api/v1/hike-trips/\(id)", method: "PATCH", token: token, body: body)
        return try decode(V1HikeTrip.self, from: data)
    }

    func deleteHikeTrip(id: String, token: String) async throws {
        _ = try await send(path: "/api/v1/hike-trips/\(id)", method: "DELETE", token: token)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SharpitAPIError.server
        }
    }

    private func send(path: String, method: String, token: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
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
        guard !(200..<300).contains(status) else { return data }
        if status == 401 || status == 403 { throw SharpitAPIError.unauthorized }
        if status == 429 { throw SharpitAPIError.rateLimited }
        if status >= 500 { throw SharpitAPIError.server }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String {
            throw SharpitAPIError.message(message)
        }
        throw SharpitAPIError.badRequest
    }
}
