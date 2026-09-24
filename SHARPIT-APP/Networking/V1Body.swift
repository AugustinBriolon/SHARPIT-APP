import Foundation

/// `GET /api/v1/body/overview` — every Corps metric in one read (`projectV1BodyOverview` in the
/// web's `src/lib/body/body-v1.ts`). A metric without data is absent from `metrics`.
nonisolated struct V1BodyOverview: Decodable, Sendable, Equatable {
    let apiVersion: Int
    let metrics: [V1BodyMetric]
    /// Web-owned (ADR-045); null until the method ships.
    let biologicalAge: V1BiologicalAge?

    private enum CodingKeys: String, CodingKey {
        case apiVersion, metrics, biologicalAge
    }

    init(apiVersion: Int = 1, metrics: [V1BodyMetric], biologicalAge: V1BiologicalAge? = nil) {
        self.apiVersion = apiVersion
        self.metrics = metrics
        self.biologicalAge = biologicalAge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        // A key this build does not know (the web added a metric) is skipped, not fatal.
        metrics = try container.decode([Lossy<V1BodyMetric>].self, forKey: .metrics).compactMap(\.value)
        biologicalAge = try? container.decodeIfPresent(V1BiologicalAge.self, forKey: .biologicalAge)
    }
}

nonisolated struct V1BodyMetric: Decodable, Sendable, Equatable {
    let key: CorpsMetricKey
    let value: Double
    let unit: String
    let previous: Double?
    let deltaWindowDays: Int?
    let baseline: V1BodyBand?
    let measuredAt: Date
    /// Lowercase provider: `withings`, `garmin`, `renpho`, `apple_health`, `profile`, `manual`…
    let source: String

    private enum CodingKeys: String, CodingKey {
        case key, value, unit, previous, deltaWindowDays, baseline, measuredAt, source
    }

    init(
        key: CorpsMetricKey,
        value: Double,
        unit: String = "",
        previous: Double? = nil,
        deltaWindowDays: Int? = nil,
        baseline: V1BodyBand? = nil,
        measuredAt: Date,
        source: String
    ) {
        self.key = key
        self.value = value
        self.unit = unit
        self.previous = previous
        self.deltaWindowDays = deltaWindowDays
        self.baseline = baseline
        self.measuredAt = measuredAt
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .key)
        guard let key = CorpsMetricKey(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .key, in: container, debugDescription: "Unknown metric \(raw)")
        }
        self.key = key
        value = try container.decode(Double.self, forKey: .value)
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        previous = try container.decodeIfPresent(Double.self, forKey: .previous)
        deltaWindowDays = try container.decodeIfPresent(Int.self, forKey: .deltaWindowDays)
        baseline = try container.decodeIfPresent(V1BodyBand.self, forKey: .baseline)
        measuredAt = try Date.fromAPI(try container.decode(String.self, forKey: .measuredAt))
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
    }
}

nonisolated struct V1BodyBand: Decodable, Sendable, Equatable {
    let low: Double
    let high: Double
}

nonisolated struct V1BiologicalAge: Decodable, Sendable, Equatable {
    let years: Double
    let chronologicalYears: Double?
    let method: String?
    let confidence: Double?
    let computedAt: String?
}

/// `GET /api/v1/body/series?metric=&range=` — one metric, oldest first, days as `YYYY-MM-DD`.
nonisolated struct V1BodySeries: Decodable, Sendable, Equatable {
    nonisolated struct Point: Decodable, Sendable, Equatable {
        let date: String
        let value: Double
    }

    nonisolated struct BandPoint: Decodable, Sendable, Equatable {
        let date: String
        let low: Double
        let high: Double
    }

    let metric: String
    let range: String
    let points: [Point]
    let baseline: [BandPoint]?
}

/// The ranges the series route accepts, as the drawer names them.
extension CorpsRange {
    nonisolated var apiValue: String {
        switch self {
        case .thirtyDays: "30d"
        case .ninetyDays: "90d"
        case .year: "1y"
        case .all: "all"
        }
    }
}

/// Decodes an element or nothing, so one unknown entry does not fail a whole list.
nonisolated struct Lossy<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

nonisolated protocol BodyServing: Sendable {
    func bodyOverview(token: String) async throws -> V1BodyOverview
    func bodySeries(metric: CorpsMetricKey, range: CorpsRange, token: String) async throws -> V1BodySeries
}

/// `/api/v1/body/*` — the Corps tab's native projection.
actor BodyClient: BodyServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func bodyOverview(token: String) async throws -> V1BodyOverview {
        try await get(V1BodyOverview.self, path: "/api/v1/body/overview", query: [], token: token)
    }

    func bodySeries(metric: CorpsMetricKey, range: CorpsRange, token: String) async throws -> V1BodySeries {
        try await get(
            V1BodySeries.self,
            path: "/api/v1/body/series",
            query: [
                URLQueryItem(name: "metric", value: metric.rawValue),
                URLQueryItem(name: "range", value: range.apiValue),
            ],
            token: token
        )
    }

    private func get<Payload: Decodable>(
        _: Payload.Type,
        path: String,
        query: [URLQueryItem],
        token: String
    ) async throws -> Payload {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url = url.appending(queryItems: query) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { throw SharpitAPIError.unauthorized }
            throw SharpitAPIError.server
        }
        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw SharpitAPIError.server
        }
    }
}
