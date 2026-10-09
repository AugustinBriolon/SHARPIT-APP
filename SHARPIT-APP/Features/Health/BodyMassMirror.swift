import Foundation

/// Pure rules for mirroring a weigh-in into Apple Santé without duplicating the same sample
/// on every Corps load.
nonisolated enum BodyMassMirror {
    /// Kilograms within this of an existing sample count as the same reading.
    static let kgTolerance = 0.05
    /// Timestamps within this window are the same weigh-in.
    static let dateTolerance: TimeInterval = 1

    /// Whether an own sample already mirrors this measuredAt + kg pair.
    static func alreadyMirrored(
        kg: Double,
        at date: Date,
        existingOwn: [(kg: Double, at: Date)]
    ) -> Bool {
        existingOwn.contains { sample in
            abs(sample.at.timeIntervalSince(date)) < dateTolerance
                && abs(sample.kg - kg) < kgTolerance
        }
    }

    /// Own samples at the same timestamp that should be replaced before writing a new kg.
    static func ownSamplesToReplace(
        at date: Date,
        existingOwn: [(id: String, kg: Double, at: Date)]
    ) -> [String] {
        existingOwn.compactMap { sample in
            abs(sample.at.timeIntervalSince(date)) < dateTolerance ? sample.id : nil
        }
    }
}
