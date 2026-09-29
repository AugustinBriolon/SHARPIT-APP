import CoreLocation
import Foundation
import HealthKit

/// One Apple Health workout in the shape `/api/v1/health-workouts` stores as an activity:
/// the summary Apple Health keeps, and its streams aligned on time.
nonisolated struct HealthWorkout: Encodable, Equatable, Sendable {
    /// SharpIt's sport, as the server's `ActivityType`.
    enum Sport: String, Encodable, Sendable {
        case run = "RUN"
        case bike = "BIKE"
        case swim = "SWIM"
        case strength = "STRENGTH"
        case hike = "HIKE"
        case other = "OTHER"
    }

    let id: String
    let type: Sport
    let title: String
    let start: Date
    let end: Date
    let durationSec: Int
    var distanceM: Double?
    var energyKcal: Double?
    var avgHr: Int?
    var maxHr: Int?
    var elevationM: Double?
    var avgPowerW: Double?
    var avgCadence: Double?
    var stream: HealthWorkoutStream?

    private enum CodingKeys: String, CodingKey {
        case id, type, title, start, durationSec, distanceM, energyKcal
        case avgHr, maxHr, elevationM, avgPowerW, avgCadence, stream
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(start.formatted(.iso8601), forKey: .start)
        try container.encode(durationSec, forKey: .durationSec)
        try container.encodeIfPresent(distanceM, forKey: .distanceM)
        try container.encodeIfPresent(energyKcal, forKey: .energyKcal)
        try container.encodeIfPresent(avgHr, forKey: .avgHr)
        try container.encodeIfPresent(maxHr, forKey: .maxHr)
        try container.encodeIfPresent(elevationM, forKey: .elevationM)
        try container.encodeIfPresent(avgPowerW, forKey: .avgPowerW)
        try container.encodeIfPresent(avgCadence, forKey: .avgCadence)
        try container.encodeIfPresent(stream, forKey: .stream)
    }
}

extension HealthWorkout.Sport {
    /// Apple's activity type to SharpIt's sport; a walk counts as a hike, as on Garmin.
    nonisolated init(activityType: HKWorkoutActivityType) {
        switch activityType {
        case .running: self = .run
        case .cycling, .handCycling: self = .bike
        case .swimming: self = .swim
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining,
             .highIntensityIntervalTraining, .coreTraining:
            self = .strength
        case .hiking, .walking: self = .hike
        default: self = .other
        }
    }

    /// Apple Health gives a workout no name; the activity list shows this one.
    nonisolated func title(for activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running: "Course à pied"
        case .cycling, .handCycling: "Vélo"
        case .swimming: "Natation"
        case .walking: "Marche"
        case .hiking: "Randonnée"
        case .yoga: "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: "Renforcement"
        case .crossTraining, .highIntensityIntervalTraining: "Entraînement fractionné"
        default: "Séance"
        }
    }

    /// Where Apple Health keeps this sport's distance.
    nonisolated var distanceType: HKQuantityTypeIdentifier? {
        switch self {
        case .run, .hike: .distanceWalkingRunning
        case .bike: .distanceCycling
        case .swim: .distanceSwimming
        case .strength, .other: nil
        }
    }
}

/// A workout's streams as SharpIt stores them: every series on the same `time` axis, in seconds
/// from the start.
nonisolated struct HealthWorkoutStream: Encodable, Equatable, Sendable {
    var time: [Double] = []
    var heartrate: [Double?]?
    var distance: [Double?]?
    var altitude: [Double?]?
    var velocity: [Double?]?
    var latlng: [[Double]]?
}

/// One reading of a workout's route.
nonisolated struct HealthRoutePoint: Equatable, Sendable {
    let date: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    /// Metres per second; nil when the location carries none.
    let speed: Double?
}

/// Lays a workout's heart rate and route on one time grid, as a provider's streams are.
///
/// Apple Health keeps heart rate every few seconds and the route about every second, each on its
/// own clock; SharpIt's stream readers expect one axis. Each series reads its last value at or
/// before each tick, so a gap holds the value before it rather than inventing a slope.
nonisolated enum HealthWorkoutStreamBuilder {
    /// The server's cap per series.
    static let maxPoints = 8_000
    static let preferredStep: TimeInterval = 5

    static func build(
        start: Date,
        durationSec: Int,
        heartRate: [(date: Date, bpm: Double)],
        route: [HealthRoutePoint]
    ) -> HealthWorkoutStream? {
        guard durationSec > 0, !heartRate.isEmpty || !route.isEmpty else { return nil }
        let step = max(preferredStep, Double(durationSec) / Double(maxPoints - 1))
        let time = Array(stride(from: 0, through: Double(durationSec), by: step))

        var stream = HealthWorkoutStream(time: time)
        if !heartRate.isEmpty {
            let samples = heartRate.sorted { $0.date < $1.date }
            stream.heartrate = sample(time, start: start, from: samples.map { ($0.date, $0.bpm) })
        }
        if !route.isEmpty {
            let points = route.sorted { $0.date < $1.date }
            // Before the first fix the athlete is where the route starts.
            let located = sampleIndex(time, start: start, dates: points.map(\.date)).map { $0 ?? 0 }
            let cumulative = cumulativeDistance(points)
            stream.latlng = located.map { [points[$0].latitude, points[$0].longitude] }
            stream.distance = located.map { cumulative[$0] }
            stream.altitude = located.map { points[$0].altitude }
            stream.velocity = located.map { points[$0].speed }
        }
        return stream
    }

    private static func sample(_ time: [Double], start: Date, from samples: [(Date, Double)]) -> [Double?] {
        sampleIndex(time, start: start, dates: samples.map(\.0)).map { $0.map { samples[$0].1 } }
    }

    /// For each tick, the index of the last reading at or before it.
    private static func sampleIndex(_ time: [Double], start: Date, dates: [Date]) -> [Int?] {
        var result: [Int?] = []
        result.reserveCapacity(time.count)
        var cursor = -1
        for tick in time {
            let instant = start.addingTimeInterval(tick)
            while cursor + 1 < dates.count, dates[cursor + 1] <= instant {
                cursor += 1
            }
            result.append(cursor >= 0 ? cursor : nil)
        }
        return result
    }

    private static func cumulativeDistance(_ points: [HealthRoutePoint]) -> [Double] {
        var total = 0.0
        var result = [0.0]
        for index in points.indices.dropFirst() {
            let previous = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
            let current = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
            total += current.distance(from: previous)
            result.append(total)
        }
        return result
    }
}
