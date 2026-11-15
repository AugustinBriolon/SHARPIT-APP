import Foundation
import HealthKit

/// Writes Sharpit-owned samples into Apple Santé (nutrition day totals, body mass, and the
/// strength session followed on the phone).
protocol HealthWriting: Sendable {
    func saveNutritionDay(
        day: String,
        kcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double
    ) async throws
    func saveBodyMass(kg: Double, at date: Date) async throws
}

/// Apple Santé on this iPhone — share types requested with `HealthKitReader`.
final class HealthKitWriter: HealthWriting, @unchecked Sendable {
    private let store = HKHealthStore()

    static let shareTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = []
        let quantities: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .bodyMass,
        ]
        for identifier in quantities {
            types.insert(HKQuantityType(identifier))
        }
        types.insert(HKWorkoutType.workoutType())
        return types
    }()

    /// The strength session followed on the phone, as a workout in Apple Santé: its start, its
    /// end, its name. Asks for the right to write workouts the first time (an athlete linked
    /// before this existed never was), and writes nothing the athlete refuses.
    func saveStrengthWorkout(activityId: String, title: String, start: Date, end: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable(), let interval = StrengthWorkoutMirror.interval(start: start, end: end) else { return }
        try await store.requestAuthorization(toShare: [HKWorkoutType.workoutType()], read: [])
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: interval.start)
        try await builder.addMetadata([
            HKMetadataKeyWorkoutBrandName: title,
            HKMetadataKeyExternalUUID: activityId,
        ])
        try await builder.endCollection(at: interval.end)
        _ = try await builder.finishWorkout()
    }

    func saveNutritionDay(
        day: String,
        kcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double
    ) async throws {
        guard let interval = Self.dayInterval(day) else { return }
        try await replaceQuantity(.dietaryEnergyConsumed, value: kcal, unit: .kilocalorie(), in: interval)
        try await replaceQuantity(.dietaryProtein, value: proteinG, unit: .gram(), in: interval)
        try await replaceQuantity(.dietaryCarbohydrates, value: carbsG, unit: .gram(), in: interval)
        try await replaceQuantity(.dietaryFatTotal, value: fatG, unit: .gram(), in: interval)
    }

    func saveBodyMass(kg: Double, at date: Date) async throws {
        let type = HKQuantityType(.bodyMass)
        let unit = HKUnit.gramUnit(with: .kilo)
        let own = try await ownBodyMassSamples(around: date)
        if BodyMassMirror.alreadyMirrored(
            kg: kg,
            at: date,
            existingOwn: own.map { ($0.quantity.doubleValue(for: unit), $0.startDate) }
        ) {
            return
        }
        // Replace our samples at that timestamp so a changed kg does not stack duplicates.
        for sample in own where abs(sample.startDate.timeIntervalSince(date)) < BodyMassMirror.dateTolerance {
            try await store.delete(sample)
        }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: kg),
            start: date,
            end: date,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        try await store.save(sample)
    }

    /// Save the new day total first, then delete prior samples excluding it — a failed save
    /// must not empty the nutrition day.
    private func replaceQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        value: Double,
        unit: HKUnit,
        in interval: DateInterval
    ) async throws {
        let type = HKQuantityType(identifier)
        guard value > 0 else {
            let predicate = HKQuery.predicateForSamples(
                withStart: interval.start,
                end: interval.end,
                options: .strictStartDate
            )
            try await store.deleteObjects(of: type, predicate: predicate)
            return
        }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: interval.start,
            end: interval.end,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        try await store.save(sample)
        let dayPredicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        let excludeNew = NSCompoundPredicate(andPredicateWithSubpredicates: [
            dayPredicate,
            NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObject(with: sample.uuid)),
        ])
        try await store.deleteObjects(of: type, predicate: excludeNew)
    }

    private func ownBodyMassSamples(around date: Date) async throws -> [HKQuantitySample] {
        let type = HKQuantityType(.bodyMass)
        let start = date.addingTimeInterval(-BodyMassMirror.dateTolerance)
        let end = date.addingTimeInterval(BodyMassMirror.dateTolerance)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            store.execute(Self.bodyMassQuery(type: type, predicate: predicate, continuation: continuation))
        }
        let bundleId = Bundle.main.bundleIdentifier
        return samples.filter { $0.sourceRevision.source.bundleIdentifier == bundleId }
    }

    /// Built outside the main actor: HealthKit calls the handler on its own queue, where a
    /// main-actor closure would trap.
    nonisolated private static func bodyMassQuery(
        type: HKQuantityType,
        predicate: NSPredicate,
        continuation: CheckedContinuation<[HKQuantitySample], Error>
    ) -> HKSampleQuery {
        HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, results, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
        }
    }

    /// `yyyy-MM-dd` in the athlete's current calendar → that local day.
    static func dayInterval(_ day: String, calendar: Calendar = .current) -> DateInterval? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}

/// What makes a strength session a workout Apple Santé can hold, and how the app tells its own
/// workouts apart when it reads Santé back.
nonisolated enum StrengthWorkoutMirror {
    /// The session's span; nil for one that ends before it starts or lasts under a minute.
    static func interval(start: Date, end: Date) -> DateInterval? {
        end.timeIntervalSince(start) >= 60 ? DateInterval(start: start, end: end) : nil
    }

    /// A workout SharpIt wrote itself: the server already holds that session, so importing it
    /// from Santé would log it twice.
    static func isOwn(sourceBundleIdentifier: String, app: String? = Bundle.main.bundleIdentifier) -> Bool {
        app != nil && sourceBundleIdentifier == app
    }
}
