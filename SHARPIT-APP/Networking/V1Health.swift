import Foundation

/// `/api/v1/health/overview` — Santé as the web reads it (SHARPIT ADR-053): each marker against a
/// published norm and the athlete's own month, grouped by how much it says about health, and what
/// deserves attention now. The app lays it out; it computes none of it.
nonisolated struct V1HealthOverview: Decodable, Equatable, Sendable {
    let synthesis: V1HealthSynthesis
    let watch: [V1HealthWatch]
    let vitals: [V1HealthMarker]
    let body: [V1HealthMarker]
    let daily: [V1HealthMarker]

    var isEmpty: Bool { vitals.isEmpty && body.isEmpty && daily.isEmpty && watch.isEmpty }

    var allMarkers: [V1HealthMarker] { vitals + body + daily }

    func marker(_ key: V1HealthMarker.Key) -> V1HealthMarker? {
        allMarkers.first { $0.key == key }
    }

    init(
        synthesis: V1HealthSynthesis,
        watch: [V1HealthWatch] = [],
        vitals: [V1HealthMarker] = [],
        body: [V1HealthMarker] = [],
        daily: [V1HealthMarker] = []
    ) {
        self.synthesis = synthesis
        self.watch = watch
        self.vitals = vitals
        self.body = body
        self.daily = daily
    }

    private enum CodingKeys: String, CodingKey {
        case synthesis, watch, vitals, body, daily
    }

    /// A marker the app does not know yet is dropped, not the whole page.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        synthesis = try container.decode(V1HealthSynthesis.self, forKey: .synthesis)
        watch = (try? container.decode([Tolerant<V1HealthWatch>].self, forKey: .watch))?.compactMap(\.value) ?? []
        vitals = Self.markers(in: container, forKey: .vitals)
        body = Self.markers(in: container, forKey: .body)
        daily = Self.markers(in: container, forKey: .daily)
    }

    private static func markers(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [V1HealthMarker] {
        (try? container.decode([Tolerant<V1HealthMarker>].self, forKey: key))?.compactMap(\.value) ?? []
    }
}

/// Decodes an element or nothing, so one unknown entry never costs its whole list.
private nonisolated struct Tolerant<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

nonisolated struct V1HealthSynthesis: Decodable, Equatable, Sendable {
    let biologicalAge: V1BiologicalAge?
    let biologicalAgeRequiresPro: Bool
    /// Markers read against a norm, and how many of them are not flagged.
    let normed: Int
    let inNorm: Int
    let highlights: [V1HealthHighlight]

    init(
        biologicalAge: V1BiologicalAge? = nil,
        biologicalAgeRequiresPro: Bool = false,
        normed: Int = 0,
        inNorm: Int = 0,
        highlights: [V1HealthHighlight] = []
    ) {
        self.biologicalAge = biologicalAge
        self.biologicalAgeRequiresPro = biologicalAgeRequiresPro
        self.normed = normed
        self.inNorm = inNorm
        self.highlights = highlights
    }

    private enum CodingKeys: String, CodingKey {
        case biologicalAge, biologicalAgeAccess, normed, inNorm, highlights
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        biologicalAgeRequiresPro = (try? container.decode(String.self, forKey: .biologicalAgeAccess)) == "pro_required"
        // The web never sends it below Pro; were it ever to, it is not kept.
        biologicalAge = biologicalAgeRequiresPro
            ? nil
            : try? container.decodeIfPresent(V1BiologicalAge.self, forKey: .biologicalAge)
        normed = (try? container.decode(Int.self, forKey: .normed)) ?? 0
        inNorm = (try? container.decode(Int.self, forKey: .inNorm)) ?? 0
        highlights = (try? container.decode([Tolerant<V1HealthHighlight>].self, forKey: .highlights))?
            .compactMap(\.value) ?? []
    }
}

nonisolated struct V1HealthHighlight: Decodable, Equatable, Sendable {
    let key: V1HealthMarker.Key
    let delta: Double
    let tone: V1HealthTone
}

nonisolated enum V1HealthTone: String, Decodable, Equatable, Sendable {
    case good
    case neutral
    case watch
}

nonisolated struct V1HealthNorm: Decodable, Equatable, Sendable {
    let band: String
    let label: String
    let tone: V1HealthTone
    /// The published source of the band, said under the marker.
    let reference: String
}

nonisolated struct V1HealthTrend: Decodable, Equatable, Sendable {
    let recent: Double
    let baseline: Double
    let delta: Double
    /// Within the marker's everyday noise: not a change worth naming.
    let stable: Bool
    let tone: V1HealthTone

    init(recent: Double, baseline: Double, delta: Double, stable: Bool, tone: V1HealthTone) {
        self.recent = recent
        self.baseline = baseline
        self.delta = delta
        self.stable = stable
        self.tone = tone
    }

    private enum CodingKeys: String, CodingKey {
        case recent, baseline, delta, stable, tone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recent = try container.decode(Double.self, forKey: .recent)
        baseline = try container.decode(Double.self, forKey: .baseline)
        delta = try container.decode(Double.self, forKey: .delta)
        tone = try container.decode(V1HealthTone.self, forKey: .tone)
        stable = (try? container.decode(Bool.self, forKey: .stable)) ?? (tone == .neutral)
    }
}

nonisolated struct V1HealthMarker: Decodable, Equatable, Identifiable, Sendable {
    enum Key: String, Decodable, Sendable {
        case restingHr, hrv, sleep, vo2max
        case weight, bodyFatPct, visceralFat, musclePct
        case steps, respiration
    }

    enum Basis: String, Decodable, Sendable {
        /// The mean of the last 7 days.
        case average7
        case latest
    }

    let key: Key
    let value: Double
    let basis: Basis
    let measuredAt: Date?
    let norm: V1HealthNorm?
    let trend: V1HealthTrend?
    /// The last 30 days, oldest first.
    let series: [CorpsPoint]
    let target: Double?

    var id: String { key.rawValue }

    init(
        key: Key,
        value: Double,
        basis: Basis = .latest,
        measuredAt: Date? = nil,
        norm: V1HealthNorm? = nil,
        trend: V1HealthTrend? = nil,
        series: [CorpsPoint] = [],
        target: Double? = nil
    ) {
        self.key = key
        self.value = value
        self.basis = basis
        self.measuredAt = measuredAt
        self.norm = norm
        self.trend = trend
        self.series = series
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case key, value, basis, measuredAt, norm, trend, series, target
    }

    private struct Point: Decodable {
        let date: String
        let value: Double
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(Key.self, forKey: .key)
        value = try container.decode(Double.self, forKey: .value)
        basis = (try? container.decode(Basis.self, forKey: .basis)) ?? .latest
        measuredAt = (try? container.decode(String.self, forKey: .measuredAt)).flatMap { try? Date.fromAPI($0) }
        norm = try? container.decodeIfPresent(V1HealthNorm.self, forKey: .norm)
        trend = try? container.decodeIfPresent(V1HealthTrend.self, forKey: .trend)
        series = ((try? container.decode([Point].self, forKey: .series)) ?? []).compactMap { point in
            TrainingDayId.date(point.date).map { CorpsPoint(date: $0, value: point.value) }
        }
        target = try? container.decodeIfPresent(Double.self, forKey: .target)
    }
}

nonisolated struct V1HealthWatch: Decodable, Equatable, Identifiable, Sendable {
    /// A marker's key, or `zone` for a sensitive zone.
    let key: String
    let title: String
    let detail: String

    var id: String { key + title }
}
