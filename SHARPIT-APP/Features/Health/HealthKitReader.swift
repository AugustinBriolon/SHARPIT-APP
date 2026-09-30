import CoreLocation
import Foundation
import HealthKit

/// Reads Apple Health. A protocol so the upload can be tested without a health store.
protocol HealthReading: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func dailySummaries(since: Date) async -> [HealthDailySummary]
    /// Workouts that ended in `interval`, oldest first, with their streams.
    func workouts(endingIn interval: DateInterval) async -> [HealthWorkout]
}

/// Apple Health on this iPhone, read only.
final class HealthKitReader: HealthReading, @unchecked Sendable {
    // HKHealthStore is thread-safe; Apple documents it for use from any queue.
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKWorkoutType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        let quantities: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRateVariabilitySDNN, .heartRate, .stepCount,
            .activeEnergyBurned, .bodyMass, .respiratoryRate, .oxygenSaturation, .vo2Max,
            // A workout's own figures, read when it is sent as an activity.
            .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
            .runningPower, .cyclingPower, .cyclingCadence,
        ]
        for identifier in quantities {
            types.insert(HKQuantityType(identifier))
        }
        return types
    }()

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: - Daily summaries for upload

    func dailySummaries(since: Date) async -> [HealthDailySummary] {
        async let nights = sleepNights(since: since)
        async let resting = dailyValues(.restingHeartRate, unit: .count().unitDivided(by: .minute()), since: since, sum: false)
        async let hrv = dailyValues(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: since, sum: false)
        async let steps = dailyValues(.stepCount, unit: .count(), since: since, sum: true)
        async let energy = dailyValues(.activeEnergyBurned, unit: .kilocalorie(), since: since, sum: true)
        async let mass = dailyValues(.bodyMass, unit: .gramUnit(with: .kilo), since: since, sum: false)
        return HealthDailySummary.merge(
            nights: await nights,
            restingHeartRate: await resting,
            hrv: await hrv,
            steps: await steps,
            activeEnergy: await energy,
            bodyMass: await mass
        )
    }

    private func dailyValues(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        since: Date,
        sum: Bool
    ) async -> [String: Double] {
        let type = HKQuantityType(identifier)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil)),
            options: sum ? .cumulativeSum : .discreteAverage,
            anchorDate: Calendar.current.startOfDay(for: since),
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var values: [String: Double] = [:]
        collection.enumerateStatistics(from: since, to: .now) { statistics, _ in
            let quantity = sum ? statistics.sumQuantity() : statistics.averageQuantity()
            if let quantity {
                values[TrainingDayId.today(now: statistics.startDate)] = quantity.doubleValue(for: unit)
            }
        }
        return values
    }

    private func sleepNights(since: Date) async -> [HealthSleepSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(
                type: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: since, end: nil)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.compactMap { sample in
            guard let stage = HealthSleepSample.Stage(healthValue: sample.value) else { return nil }
            return HealthSleepSample(
                start: sample.startDate,
                end: sample.endDate,
                stage: stage,
                source: sample.sourceRevision.source.name
            )
        }
    }

    // MARK: - Workouts for upload

    func workouts(endingIn interval: DateInterval) async -> [HealthWorkout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictEndDate))],
            sortDescriptors: [SortDescriptor(\.endDate)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        var result: [HealthWorkout] = []
        for workout in workouts {
            result.append(await healthWorkout(from: workout))
        }
        return result
    }

    private func healthWorkout(from workout: HKWorkout) async -> HealthWorkout {
        let activityType = workout.workoutActivityType
        let sport = HealthWorkout.Sport(activityType: activityType)
        let durationSec = max(1, Int(workout.duration.rounded()))
        let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
        let bpm = HKUnit.count().unitDivided(by: .minute())

        var summary = HealthWorkout(
            id: workout.uuid.uuidString,
            type: sport,
            title: sport.title(for: activityType),
            start: workout.startDate,
            end: workout.endDate,
            durationSec: durationSec
        )
        if let zone = (workout.metadata?[HKMetadataKeyTimeZone] as? String).flatMap(TimeZone.init(identifier:)) {
            summary.timeZone = zone
        }
        summary.distanceM = sport.distanceType.flatMap {
            workout.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter())
        }
        summary.energyKcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        summary.avgHr = heartRate?.averageQuantity().map { Int($0.doubleValue(for: bpm).rounded()) }
        summary.maxHr = heartRate?.maximumQuantity().map { Int($0.doubleValue(for: bpm).rounded()) }
        summary.elevationM = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter())
        summary.avgPowerW = workout.statistics(for: HKQuantityType(sport == .bike ? .cyclingPower : .runningPower))?
            .averageQuantity()?.doubleValue(for: .watt())
        if sport == .bike {
            summary.avgCadence = workout.statistics(for: HKQuantityType(.cyclingCadence))?
                .averageQuantity()?.doubleValue(for: bpm)
        }

        async let samples = heartRateSamples(during: workout, unit: bpm)
        async let route = routePoints(of: workout)
        summary.stream = HealthWorkoutStreamBuilder.build(
            start: workout.startDate,
            durationSec: durationSec,
            heartRate: await samples,
            route: await route
        )
        return summary
    }

    private func heartRateSamples(during workout: HKWorkout, unit: HKUnit) async -> [(date: Date, bpm: Double)] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(.heartRate),
                predicate: HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    private func routePoints(of workout: HKWorkout) async -> [HealthRoutePoint] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let routes = try? await descriptor.result(for: store) else { return [] }
        var points: [HealthRoutePoint] = []
        for case let route as HKWorkoutRoute in routes {
            let locations = HKWorkoutRouteQueryDescriptor(route)
            do {
                for try await location in locations.results(for: store) {
                    points.append(HealthRoutePoint(
                        date: location.timestamp,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                        speed: location.speed >= 0 ? location.speed : nil
                    ))
                }
            } catch {
                continue
            }
        }
        return points
    }
}
