import Foundation

/// `/api/v1/records` — the athlete's best performances, as the web stores them
/// (`PerformanceRecord`, top five per category, recomputed after each activity change).
///
/// Every figure is the server's: `displayValue` is already worded (« 4:12/km », « 312 W »,
/// « 2h45 »), so the app never formats a record itself. The scatter efforts the web keeps for
/// its threshold estimates (`runEfforts`, `bikeEfforts`) are not read here.
nonisolated struct V1Records: Decodable, Sendable, Equatable {
    let prs: V1RecordGroups
    /// Best mean power per duration, shortest first. Bike only, from cached streams.
    let powerCurve: [V1PowerCurvePoint]
    /// Best times over reference distances (400 m … marathon), from cached streams.
    let runBests: [V1RunBest]
    let streamsAnalyzed: Int
    let totalActivities: Int
    let generatedAt: Date?

    init(
        prs: V1RecordGroups = V1RecordGroups(),
        powerCurve: [V1PowerCurvePoint] = [],
        runBests: [V1RunBest] = [],
        streamsAnalyzed: Int = 0,
        totalActivities: Int = 0,
        generatedAt: Date? = nil
    ) {
        self.prs = prs
        self.powerCurve = powerCurve
        self.runBests = runBests
        self.streamsAnalyzed = streamsAnalyzed
        self.totalActivities = totalActivities
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case prs, powerCurve, runBests, streamsAnalyzed, totalActivities, generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prs = (try? container.decodeIfPresent(V1RecordGroups.self, forKey: .prs)) ?? V1RecordGroups()
        powerCurve = (try? container.decodeIfPresent(LossyRecordArray<V1PowerCurvePoint>.self, forKey: .powerCurve))?.items ?? []
        runBests = (try? container.decodeIfPresent(LossyRecordArray<V1RunBest>.self, forKey: .runBests))?.items ?? []
        streamsAnalyzed = (try? container.decodeIfPresent(Int.self, forKey: .streamsAnalyzed)) ?? 0
        totalActivities = (try? container.decodeIfPresent(Int.self, forKey: .totalActivities)) ?? 0
        let generated = try? container.decodeIfPresent(String.self, forKey: .generatedAt)
        generatedAt = generated.flatMap { try? Date.fromAPI($0) }
    }

    /// Nothing recorded in any sport, and no curve: the page invites to sync instead.
    var isEmpty: Bool {
        prs.run.allSatisfy(\.entries.isEmpty)
            && prs.bike.allSatisfy(\.entries.isEmpty)
            && prs.swim.allSatisfy(\.entries.isEmpty)
            && powerCurve.isEmpty
            && runBests.allSatisfy(\.entries.isEmpty)
    }

    func categories(for sport: RecordSport) -> [V1RecordCategory] {
        switch sport {
        case .run: prs.run
        case .bike: prs.bike
        case .swim: prs.swim
        }
    }
}

/// The three sports the web keeps records for, in its tab order.
nonisolated enum RecordSport: String, CaseIterable, Identifiable, Sendable {
    case run
    case bike
    case swim

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: "Course"
        case .bike: "Vélo"
        case .swim: "Natation"
        }
    }

    var activityType: V1ActivityType {
        switch self {
        case .run: .run
        case .bike: .bike
        case .swim: .swim
        }
    }
}

nonisolated struct V1RecordGroups: Decodable, Sendable, Equatable {
    var run: [V1RecordCategory] = []
    var bike: [V1RecordCategory] = []
    var swim: [V1RecordCategory] = []

    init(run: [V1RecordCategory] = [], bike: [V1RecordCategory] = [], swim: [V1RecordCategory] = []) {
        self.run = run
        self.bike = bike
        self.swim = swim
    }

    private enum CodingKeys: String, CodingKey { case run, bike, swim }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        run = (try? container.decodeIfPresent(LossyRecordArray<V1RecordCategory>.self, forKey: .run))?.items ?? []
        bike = (try? container.decodeIfPresent(LossyRecordArray<V1RecordCategory>.self, forKey: .bike))?.items ?? []
        swim = (try? container.decodeIfPresent(LossyRecordArray<V1RecordCategory>.self, forKey: .swim))?.items ?? []
    }
}

/// One record kind — « Plus longue sortie », « Meilleure allure moyenne » — best first.
nonisolated struct V1RecordCategory: Decodable, Sendable, Equatable, Identifiable {
    let key: String
    let label: String
    let entries: [V1RecordEntry]

    var id: String { key }

    init(key: String, label: String, entries: [V1RecordEntry]) {
        self.key = key
        self.label = label
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey { case key, label, entries }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        entries = ((try? container.decodeIfPresent(LossyRecordArray<V1RecordEntry>.self, forKey: .entries))?.items ?? [])
            .sorted { $0.rank < $1.rank }
    }
}

nonisolated struct V1RecordEntry: Decodable, Sendable, Equatable, Identifiable {
    let rank: Int
    let value: Double
    /// Worded by the server: « 21,4 km », « 4:12/km ».
    let displayValue: String
    /// A second reading of the same effort — the pace under a best time.
    let sublabel: String?
    let activityId: String?
    let date: Date
    let title: String?

    var id: Int { rank }

    init(
        rank: Int,
        value: Double,
        displayValue: String,
        sublabel: String? = nil,
        activityId: String? = nil,
        date: Date,
        title: String? = nil
    ) {
        self.rank = rank
        self.value = value
        self.displayValue = displayValue
        self.sublabel = sublabel
        self.activityId = activityId
        self.date = date
        self.title = title
    }

    private enum CodingKeys: String, CodingKey {
        case rank, value, displayValue, sublabel, activityId, date, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rank = try container.decode(Int.self, forKey: .rank)
        value = try container.decode(Double.self, forKey: .value)
        displayValue = try container.decode(String.self, forKey: .displayValue)
        sublabel = try container.decodeIfPresent(String.self, forKey: .sublabel)
        activityId = try container.decodeIfPresent(String.self, forKey: .activityId)
        date = try Date.fromAPI(try container.decode(String.self, forKey: .date))
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }
}

/// The best mean power held over one duration.
nonisolated struct V1PowerCurvePoint: Decodable, Sendable, Equatable, Identifiable {
    let seconds: Int
    /// « 5 s », « 20 min ».
    let label: String
    let watts: Double
    let activityId: String?
    let date: Date
    let title: String?

    var id: Int { seconds }

    init(seconds: Int, label: String, watts: Double, activityId: String? = nil, date: Date, title: String? = nil) {
        self.seconds = seconds
        self.label = label
        self.watts = watts
        self.activityId = activityId
        self.date = date
        self.title = title
    }

    private enum CodingKeys: String, CodingKey { case seconds, label, watts, activityId, date, title }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try container.decode(Int.self, forKey: .seconds)
        label = try container.decode(String.self, forKey: .label)
        watts = try container.decode(Double.self, forKey: .watts)
        activityId = try container.decodeIfPresent(String.self, forKey: .activityId)
        date = try Date.fromAPI(try container.decode(String.self, forKey: .date))
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }
}

/// The best times over one reference distance; `value` is seconds.
nonisolated struct V1RunBest: Decodable, Sendable, Equatable, Identifiable {
    let meters: Int
    /// « 5 km », « Semi », « Mile ».
    let label: String
    let entries: [V1RecordEntry]

    var id: Int { meters }

    init(meters: Int, label: String, entries: [V1RecordEntry]) {
        self.meters = meters
        self.label = label
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey { case meters, label, entries }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meters = try container.decode(Int.self, forKey: .meters)
        label = try container.decode(String.self, forKey: .label)
        entries = ((try? container.decodeIfPresent(LossyRecordArray<V1RecordEntry>.self, forKey: .entries))?.items ?? [])
            .sorted { $0.rank < $1.rank }
    }
}

/// An array that keeps the elements it can read: one malformed record never blanks the page.
nonisolated struct LossyRecordArray<Element: Decodable & Sendable>: Decodable, Sendable {
    let items: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else if (try? container.decode(JSONValue.self)) == nil {
                // Read past it whatever it is (a failed decode does not move the container on);
                // should even that fail, stop rather than loop.
                break
            }
        }
        self.items = items
    }
}

nonisolated protocol RecordsServing: Sendable {
    func records(token: String) async throws -> V1Records
}

actor RecordsClient: RecordsServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func records(token: String) async throws -> V1Records {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/records"))
        request.httpMethod = "GET"
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
        switch status {
        case 200...299: break
        case 401, 403: throw SharpitAPIError.unauthorized
        case 429: throw SharpitAPIError.rateLimited
        default: throw SharpitAPIError.server
        }
        do {
            return try JSONDecoder().decode(V1Records.self, from: data)
        } catch {
            throw SharpitAPIError.server
        }
    }
}
