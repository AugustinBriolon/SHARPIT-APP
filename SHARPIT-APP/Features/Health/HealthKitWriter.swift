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
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date,
            end: date,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        try await store.save(sample)
    }

    /// Drop prior Sharpit samples for that type on the day, then write one cumulative sample.
    private func replaceQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        value: Double,
        unit: HKUnit,
        in interval: DateInterval
    ) async throws {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        try await store.deleteObjects(of: type, predicate: predicate)
        guard value > 0 else { return }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: interval.start,
            end: interval.end,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        try await store.save(sample)
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
