import Foundation

nonisolated enum V1ActivityType: String, Codable, Sendable {
    case run = "RUN"
    case bike = "BIKE"
    case swim = "SWIM"
    case strength = "STRENGTH"
    case hike = "HIKE"
    case triathlon = "TRIATHLON"
    case other = "OTHER"

    var label: String {
        switch self {
        case .run: "Course"
        case .bike: "Vélo"
        case .swim: "Natation"
        case .strength: "Force"
        case .hike: "Randonnée"
        case .triathlon: "Triathlon"
        case .other: "Activité"
        }
    }

    var symbolName: String {
        switch self {
        case .run: "figure.run"
        case .bike: "bicycle"
        case .swim: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .hike: "figure.hiking"
        case .triathlon: "figure.mixed.cardio"
        case .other: "figure.mind.and.body"
        }
    }

}

nonisolated struct V1ActivityListItem: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let type: V1ActivityType
    let date: Date
    let title: String?
    let duration: Double?
    let load: Double?
    let rpe: Double?
    let weather: String?
    let distanceM: Double?
    let elevationM: Double?
    let plannedSession: V1ActivityPlannedSession?

    enum CodingKeys: String, CodingKey {
        case id, type, date, title, duration, load, rpe, weather
        case runMetrics, bikeMetrics, swimMetrics, hikeMetrics, plannedSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let decodedType = try container.decodeIfPresent(V1ActivityType.self, forKey: .type) ?? .other
        type = decodedType
        date = try Date.fromAPI(container.decode(String.self, forKey: .date))
        title = try container.decodeIfPresent(String.self, forKey: .title)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        load = try container.decodeIfPresent(Double.self, forKey: .load)
        rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
        weather = try container.decodeIfPresent(String.self, forKey: .weather)
        plannedSession = try container.decodeIfPresent(V1ActivityPlannedSession.self, forKey: .plannedSession)

        let metrics = try container.decodeIfPresent(V1ActivityMetricBundle.self, forKey: Self.metricsKey(for: type))
        distanceM = metrics?.distanceM
        elevationM = metrics?.elevationM
    }

    private static func metricsKey(for type: V1ActivityType) -> CodingKeys {
        switch type {
        case .run: .runMetrics
        case .bike: .bikeMetrics
        case .swim: .swimMetrics
        case .hike: .hikeMetrics
        default: .runMetrics
        }
    }
}

nonisolated struct V1ActivityMetricBundle: Codable, Sendable, Equatable {
    let distanceM: Double?
    let elevationM: Double?
    let paceSecPerKm: Double?
    let avgPaceSecPer100m: Double?
    let avgHr: Double?
    let cadence: Double?
    let avgCadence: Double?
    let avgPower: Double?
    let sets: Double?
    let swolf: Double?
    let calories: Double?
}

nonisolated struct V1ActivityStrengthSet: Decodable, Sendable, Hashable {
    let exercise: String
    let sets: Int
    let reps: Int
    let durationSec: Int?
    let weightKg: Double?
}

nonisolated struct V1ActivityPlannedSession: Decodable, Sendable, Hashable {
    let id: String?
    let title: String?
    let analysis: V1PlannedSessionAnalysis?
}

nonisolated struct V1PlannedSessionAnalysis: Decodable, Sendable, Hashable {
    let complianceScore: Double?
    let verdict: String?
    let summary: String?
    let remarks: [String]?
    let recommendation: String?
}

nonisolated struct V1ActivityNarrative: Decodable, Sendable, Equatable {
    let headline: String
    let narrative: String
}

nonisolated struct V1ActivityStream: Decodable, Sendable, Equatable {
    let available: Bool
    let polyline: String?
    let data: V1ActivityStreamData?

    var route: [V1ActivityCoordinate] {
        data?.latlng ?? []
    }
}

nonisolated struct V1ActivityStreamData: Decodable, Sendable, Equatable {
    let latlng: [V1ActivityCoordinate]

    enum CodingKeys: String, CodingKey {
        case latlng
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([[Double]].self, forKey: .latlng) ?? []
        latlng = raw.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return V1ActivityCoordinate(latitude: pair[0], longitude: pair[1])
        }
    }
}

nonisolated struct V1ActivityCoordinate: Decodable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
}

nonisolated struct V1ActivityStreamSample: Decodable, Sendable, Equatable {
    let t: Double
    let d: Double
    let alt: Double?
    let hr: Double?
    let watts: Double?
    let cadence: Double?
    let speed: Double?
}

nonisolated struct V1ActivityStreamPayload: Decodable, Sendable, Equatable {
    let available: Bool
    let path: [[Double]]?
    let samples: [V1ActivityStreamSample]
    let stats: V1ActivityStreamStats?

    var route: [V1ActivityCoordinate] {
        (path ?? []).compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return V1ActivityCoordinate(latitude: pair[0], longitude: pair[1])
        }
    }
}

nonisolated struct V1ActivityStreamStats: Decodable, Sendable, Equatable {
    let totalDistance: Double?
    let avgSpeed: Double?
    let totalAscent: Double?
}

nonisolated struct V1MultisportLeg: Decodable, Sendable, Equatable, Identifiable {
    let kind: String
    let label: String
    let durationSec: Double
    let movingDurationSec: Double?
    let distanceM: Double?
    let avgHr: Double?
    let avgSpeedMs: Double?
    let elevationM: Double?
    let calories: Double?
    let transitionIndex: Int?

    var id: String {
        "\(kind)-\(transitionIndex ?? 0)-\(label)"
    }

    var activityType: V1ActivityType {
        switch kind {
        case "swim": .swim
        case "bike": .bike
        case "run": .run
        default: .other
        }
    }

    var symbolName: String {
        if kind == "transition" {
            return "arrow.triangle.2.circlepath"
        }
        return activityType.symbolName
    }
}

struct V1ActivityWeather: Sendable, Equatable {
            let city: String?
            let temperature: Double?

            init(rawValue: String?) {
                guard
                    let rawValue,
                    let data = rawValue.data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    city = rawValue
                    temperature = nil
                    return
                }
                city = object["city"] as? String
                temperature = object["avgTempC"] as? Double
            }

            var label: String? {
                switch (city, temperature) {
                case let (city?, temperature?):
                    return "\(city) · \(Int(temperature.rounded()))°"
                case let (city?, nil):
                    return city
                case let (nil, temperature?):
                    return "\(Int(temperature.rounded()))°"
                default:
                    return nil
        }
    }
}

nonisolated struct V1ActivityDetail: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let type: V1ActivityType
    let date: Date
    let title: String?
    let duration: Double?
    let load: Double?
    let rpe: Double?
    let feeling: String?
    let weather: String?
    let notes: String?
    let distanceM: Double?
    let elevationM: Double?
    let paceSecPerKm: Double?
    let avgPaceSecPer100m: Double?
    let avgHr: Double?
    let cadence: Double?
    let avgCadence: Double?
    let avgPower: Double?
    let swimSets: Double?
    let swolf: Double?
    let calories: Double?
    let strengthSets: [V1ActivityStrengthSet]
    let plannedSession: V1ActivityPlannedSession?
    let narrativeAnalysis: V1ActivityNarrative?
    let stream: V1ActivityStream?
    let multisportLegs: [V1MultisportLeg]

    static func preview(from activity: V1ActivityListItem) -> V1ActivityDetail {
        V1ActivityDetail(
            id: activity.id,
            type: activity.type,
            date: activity.date,
            title: activity.title,
            duration: activity.duration,
            load: activity.load,
            rpe: activity.rpe,
            feeling: nil,
            weather: activity.weather,
            notes: nil,
            distanceM: activity.distanceM,
            elevationM: activity.elevationM,
            paceSecPerKm: nil,
            avgPaceSecPer100m: nil,
            avgHr: nil,
            cadence: nil,
            avgCadence: nil,
            avgPower: nil,
            swimSets: nil,
            swolf: nil,
            calories: nil,
            strengthSets: [],
            plannedSession: activity.plannedSession,
            narrativeAnalysis: nil,
            stream: nil,
            multisportLegs: []
        )
    }

    private init(
        id: String,
        type: V1ActivityType,
        date: Date,
        title: String?,
        duration: Double?,
        load: Double?,
        rpe: Double?,
        feeling: String?,
        weather: String?,
        notes: String?,
        distanceM: Double?,
        elevationM: Double?,
        paceSecPerKm: Double?,
        avgPaceSecPer100m: Double?,
        avgHr: Double?,
        cadence: Double?,
        avgCadence: Double?,
        avgPower: Double?,
        swimSets: Double?,
        swolf: Double?,
        calories: Double?,
        strengthSets: [V1ActivityStrengthSet],
        plannedSession: V1ActivityPlannedSession?,
        narrativeAnalysis: V1ActivityNarrative?,
        stream: V1ActivityStream?,
        multisportLegs: [V1MultisportLeg]
    ) {
        self.id = id
        self.type = type
        self.date = date
        self.title = title
        self.duration = duration
        self.load = load
        self.rpe = rpe
        self.feeling = feeling
        self.weather = weather
        self.notes = notes
        self.distanceM = distanceM
        self.elevationM = elevationM
        self.paceSecPerKm = paceSecPerKm
        self.avgPaceSecPer100m = avgPaceSecPer100m
        self.avgHr = avgHr
        self.cadence = cadence
        self.avgCadence = avgCadence
        self.avgPower = avgPower
        self.swimSets = swimSets
        self.swolf = swolf
        self.calories = calories
        self.strengthSets = strengthSets
        self.plannedSession = plannedSession
        self.narrativeAnalysis = narrativeAnalysis
        self.stream = stream
        self.multisportLegs = multisportLegs
    }

    enum CodingKeys: String, CodingKey {
        case id, type, date, title, duration, load, rpe, feeling, weather, notes
        case runMetrics, bikeMetrics, swimMetrics, hikeMetrics, plannedSession
        case narrativeAnalysis, stream
        case strengthSets, multisportLegs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let decodedType = try container.decodeIfPresent(V1ActivityType.self, forKey: .type) ?? .other
        type = decodedType
        date = try Date.fromAPI(container.decode(String.self, forKey: .date))
        title = try container.decodeIfPresent(String.self, forKey: .title)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        load = try container.decodeIfPresent(Double.self, forKey: .load)
        rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
        feeling = try container.decodeIfPresent(String.self, forKey: .feeling)
        weather = try container.decodeIfPresent(String.self, forKey: .weather)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        plannedSession = try container.decodeIfPresent(V1ActivityPlannedSession.self, forKey: .plannedSession)
        narrativeAnalysis = try container.decodeIfPresent(V1ActivityNarrative.self, forKey: .narrativeAnalysis)
        stream = try container.decodeIfPresent(V1ActivityStream.self, forKey: .stream)
        multisportLegs = (try? container.decodeIfPresent([V1MultisportLeg].self, forKey: .multisportLegs)) ?? []

        let metrics: V1ActivityMetricBundle? = {
            switch decodedType {
            case .run: try? container.decodeIfPresent(V1ActivityMetricBundle.self, forKey: .runMetrics)
            case .bike: try? container.decodeIfPresent(V1ActivityMetricBundle.self, forKey: .bikeMetrics)
            case .swim: try? container.decodeIfPresent(V1ActivityMetricBundle.self, forKey: .swimMetrics)
            case .hike: try? container.decodeIfPresent(V1ActivityMetricBundle.self, forKey: .hikeMetrics)
            default: nil
            }
        }()
        distanceM = metrics?.distanceM
        elevationM = metrics?.elevationM
        paceSecPerKm = metrics?.paceSecPerKm
        avgPaceSecPer100m = metrics?.avgPaceSecPer100m
        avgHr = metrics?.avgHr
        cadence = metrics?.cadence
        avgCadence = metrics?.avgCadence
        avgPower = metrics?.avgPower
        swimSets = metrics?.sets
        swolf = metrics?.swolf
        calories = metrics?.calories
        strengthSets = (try? container.decodeIfPresent([V1ActivityStrengthSet].self, forKey: .strengthSets)) ?? []
    }
}

private extension Date {
    nonisolated static func fromAPI(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = fractional.date(from: value) ?? standard.date(from: value) {
            return date
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid activity date"))
    }
}
