import SwiftUI

/// Turning a weigh-in into what Corps shows.
///
/// Apart from the view so the choices can be tested: which metrics a scale actually wrote,
/// which way the weight moved, and whether a move is worth naming.
nonisolated enum BodyCompositionReadout {
    struct Tile: Identifiable, Equatable {
        let caption: String
        let value: String
        let unit: String?

        var id: String { caption }
    }

    /// One tile per metric the scale wrote, in the web's words and order. A metric the scale
    /// does not measure is absent, never shown as a dash: an empty tile reads as a broken
    /// scale rather than a scale that does not weigh body fat.
    static func tiles(_ measurement: V1BodyMeasurement) -> [Tile] {
        var tiles: [Tile] = []
        if let bodyFatPct = measurement.bodyFatPct {
            tiles.append(Tile(caption: "Masse grasse", value: percent(bodyFatPct), unit: "%"))
        }
        if let musclePct = measurement.musclePct {
            tiles.append(Tile(caption: "Muscle", value: percent(musclePct), unit: "%"))
        }
        if let waterPct = measurement.waterPct {
            tiles.append(Tile(caption: "Eau corporelle", value: percent(waterPct), unit: "%"))
        }
        if let boneKg = measurement.boneKg {
            tiles.append(Tile(caption: "Masse osseuse", value: percent(boneKg), unit: "kg"))
        }
        if let bmi = measurement.bmi {
            tiles.append(Tile(caption: "IMC", value: percent(bmi), unit: nil))
        }
        return tiles
    }

    /// Which scale wrote it, in the athlete's words. Nil when the source means nothing to
    /// them — naming an unknown provider explains less than saying nothing.
    static func scaleLabel(_ source: String?) -> String? {
        switch source?.uppercased() {
        case "WITHINGS": "Withings"
        case "RENPHO": "Renpho"
        case "GARMIN": "Garmin"
        default: nil
        }
    }

    private static func percent(_ value: Double) -> String {
        ProfileFieldFormat.decimal(value)
    }
}

/// Which way the weight has moved, and whether that is worth a word.
nonisolated enum BodyTrend {
    struct Reading: Equatable {
        let label: String
        let tone: Color
    }

    /// A scale repeats itself to within a few hundred grams, so a move under 200 g is noise.
    /// Reporting it would turn hydration into a trend.
    static let noiseThresholdKg = 0.2

    /// The delta between the latest weigh-in and one at least a week older.
    ///
    /// Neutral in tone whichever way it went: SHARPIT does not know whether this athlete is
    /// cutting or building, so a kilo is a fact, never a verdict.
    static func weight(latest: V1BodyMeasurement, reference: V1BodyMeasurement?) -> Reading? {
        guard let current = latest.weightKg,
              let previous = reference?.weightKg else { return nil }
        let delta = current - previous
        guard abs(delta) >= noiseThresholdKg else {
            return Reading(label: "Stable", tone: SharpitColor.signalNeutral)
        }
        let sign = delta > 0 ? "+" : "−"
        return Reading(
            label: sign + ProfileFieldFormat.decimal(abs(delta)) + " kg",
            tone: SharpitColor.signalNeutral
        )
    }
}
