import Foundation
import HealthKit

/// Reads Apple Health. A protocol so the diagnostic and the upload can be tested without
/// a health store.
protocol HealthReading: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func reading(for signal: HealthSignal, since: Date) async -> HealthSignalReading
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

    func reading(for signal: HealthSignal, since: Date) async -> HealthSignalReading {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        switch signal {
        case .sleep:
            return await categoryReading(.sleepAnalysis, predicate: predicate) { value in
                HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue).contains(value)
            }
        case .sleepStages:
            return await categoryReading(.sleepAnalysis, predicate: predicate) { value in
                [HKCategoryValueSleepAnalysis.asleepCore, .asleepDeep, .asleepREM].map(\.rawValue).contains(value)
            }
        case .workouts:
            return await sampleReading(HKWorkoutType.workoutType(), predicate: predicate)
        case .workoutRoutes:
            return await sampleReading(HKSeriesType.workoutRoute(), predicate: predicate)
        case .restingHeartRate: return await quantityReading(.restingHeartRate, since: since, sum: false)
        case .heartRateVariability: return await quantityReading(.heartRateVariabilitySDNN, since: since, sum: false)
        case .heartRate: return await quantityReading(.heartRate, since: since, sum: false)
        case .steps: return await quantityReading(.stepCount, since: since, sum: true)
        case .activeEnergy: return await quantityReading(.activeEnergyBurned, since: since, sum: true)
        case .bodyMass: return await quantityReading(.bodyMass, since: since, sum: false)
        case .respiratoryRate: return await quantityReading(.respiratoryRate, since: since, sum: false)
        case .oxygenSaturation: return await quantityReading(.oxygenSaturation, since: since, sum: false)
        case .vo2Max: return await quantityReading(.vo2Max, since: since, sum: false)
        case .bodyBattery, .stress, .trainingReadiness, .sleepScore:
            return .empty
        }
    }

    // MARK: - Reading presence

    private func categoryReading(
        _ identifier: HKCategoryTypeIdentifier,
        predicate: NSPredicate,
        keep: (Int) -> Bool
    ) async -> HealthSignalReading {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(identifier), predicate: predicate)],
            sortDescriptors: []
        )
        guard let samples = try? await descriptor.result(for: store) else { return .empty }
        let kept = samples.filter { keep($0.value) }
        return HealthSignalReading(
            sources: Array(Set(kept.map(\.sourceRevision.source.name))),
            days: Set(kept.map { TrainingDayId.today(now: $0.endDate) })
        )
    }

    private func sampleReading(_ type: HKSampleType, predicate: NSPredicate) async -> HealthSignalReading {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: type, predicate: predicate)],
            sortDescriptors: []
        )
        guard let samples = try? await descriptor.result(for: store) else { return .empty }
        return HealthSignalReading(
            sources: Array(Set(samples.map(\.sourceRevision.source.name))),
            days: Set(samples.map { TrainingDayId.today(now: $0.endDate) })
        )
    }

    /// Heart rate alone is thousands of samples a day, so presence is read from daily
    /// statistics and the writers from a source query, never from the raw samples.
    private func quantityReading(
        _ identifier: HKQuantityTypeIdentifier,
        since: Date,
        sum: Bool
    ) async -> HealthSignalReading {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let sourceQuery = HKSourceQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate))
        let sources = (try? await sourceQuery.result(for: store))?.map(\.name) ?? []
        let days = await daysWithData(type, since: since, sum: sum)
        return HealthSignalReading(sources: sources, days: days)
    }

    private func daysWithData(_ type: HKQuantityType, since: Date, sum: Bool) async -> Set<String> {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil)),
            options: sum ? .cumulativeSum : .discreteAverage,
            anchorDate: Calendar.current.startOfDay(for: since),
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [] }
        var days: Set<String> = []
        collection.enumerateStatistics(from: since, to: .now) { statistics, _ in
            let hasValue = sum ? statistics.sumQuantity() != nil : statistics.averageQuantity() != nil
            if hasValue { days.insert(TrainingDayId.today(now: statistics.startDate)) }
        }
        return days
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
