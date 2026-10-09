import Foundation
import HealthKit

/// Writes Sharpit-owned samples into Apple Santé (nutrition day totals + body mass).
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
        return types
    }()

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
            let query = HKSampleQuery(
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
            store.execute(query)
        }
        let bundleId = Bundle.main.bundleIdentifier
        return samples.filter { $0.sourceRevision.source.bundleIdentifier == bundleId }
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
