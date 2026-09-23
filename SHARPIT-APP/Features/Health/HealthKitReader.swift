import Foundation
import HealthKit

/// Reads Apple Health. A protocol so the upload can be tested without a health store.
protocol HealthReading: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func dailySummaries(since: Date) async -> [HealthDailySummary]
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
}
