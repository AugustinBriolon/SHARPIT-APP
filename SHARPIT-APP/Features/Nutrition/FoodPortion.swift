import Foundation

/// What a portion weighs in nutrients — the web's `portionNutrients` (food-log-math.ts): per
/// 100 g × grams, rounded to 0.1. Only for the preview on screen: the server snapshots the
/// entry's nutrients itself, so the two can never disagree on what was logged.
nonisolated enum FoodPortion {
    struct Nutrients: Equatable, Sendable {
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
    }

    /// One of the quick picks above the grams field.
    struct Preset: Equatable, Hashable, Sendable, Identifiable {
        let label: String
        let grams: Double

        var id: Double { grams }
    }

    static func nutrients(of product: V1FoodProduct, grams: Double) -> Nutrients {
        Nutrients(
            kcal: scale(product.kcalPer100g, grams),
            protein: scale(product.proteinPer100g, grams),
            carbs: scale(product.carbsPer100g, grams),
            fat: scale(product.fatPer100g, grams)
        )
    }

    /// A logged entry at a new weight, as the server rescales it.
    static func nutrients(of entry: V1FoodLogEntry, grams: Double) -> Nutrients {
        guard entry.grams > 0 else {
            return Nutrients(kcal: entry.kcal, protein: entry.protein, carbs: entry.carbs, fat: entry.fat)
        }
        let ratio = grams / entry.grams
        return Nutrients(
            kcal: round1(entry.kcal * ratio),
            protein: round1(entry.protein * ratio),
            carbs: round1(entry.carbs * ratio),
            fat: round1(entry.fat * ratio)
        )
    }

    /// 100 g, the product's own serving when it has one, and the weight last logged — each once.
    static func presets(for product: V1FoodProduct, lastGrams: Double?) -> [Preset] {
        var presets = [Preset(label: "100 g", grams: 100)]
        if let serving = product.servingGrams, serving > 0 {
            let label = product.servingLabel.map { "\($0) · \(gramsLabel(serving))" } ?? "1 portion · \(gramsLabel(serving))"
            presets.append(Preset(label: label, grams: serving))
        }
        if let lastGrams, lastGrams > 0 {
            presets.append(Preset(label: "Dernière fois · \(gramsLabel(lastGrams))", grams: lastGrams))
        }
        var seen = Set<Double>()
        return presets.filter { seen.insert($0.grams).inserted }
    }

    /// The weight a product opens on: what was logged last, else its serving, else 100 g.
    static func initialGrams(for product: V1FoodProduct, lastGrams: Double?) -> Double {
        if let lastGrams, lastGrams > 0 { return lastGrams }
        if let serving = product.servingGrams, serving > 0 { return serving }
        return 100
    }

    /// `150 g`, `12,5 g`.
    static func gramsLabel(_ grams: Double) -> String {
        "\(grams.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR")))) g"
    }

    /// `12,5` — a grams or macro figure with at most one decimal, French separator.
    static func figure(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR")))
    }

    /// `2400`, `12,5` — the same without grouping, so a field shows what it parses back.
    static func editableFigure(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "fr_FR")))
    }

    private static func scale(_ per100g: Double, _ grams: Double) -> Double {
        round1(per100g * grams / 100)
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

/// A scanned code as the server takes it: EAN-8, UPC-A, EAN-13 or GTIN-14 digits only. Anything
/// else (a QR code, a shipping label) is not a food and is ignored while scanning goes on.
nonisolated enum FoodBarcode {
    static func normalized(_ payload: String?) -> String? {
        guard let payload else { return nil }
        let code = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.allSatisfy(\.isASCIIDigitCharacter) else { return nil }
        return code.count == 8 || (12...14).contains(code.count) ? code : nil
    }
}

private extension Character {
    nonisolated var isASCIIDigitCharacter: Bool { isASCII && isNumber }
}

/// The targets form as typed: empty clears a target, anything out of the server's range is refused.
nonisolated enum NutritionTargetsInput {
    static let kcalRange = 800...8000
    static let proteinRange = 0.0...600
    static let carbsRange = 0.0...1500
    static let fatRange = 0.0...500

    /// Nil when one field holds something the server would refuse.
    static func parse(kcal: String, protein: String, carbs: String, fat: String) -> V1NutritionTargets? {
        guard let kcalValue = field(kcal, in: Double(kcalRange.lowerBound)...Double(kcalRange.upperBound)),
              let proteinValue = field(protein, in: proteinRange),
              let carbsValue = field(carbs, in: carbsRange),
              let fatValue = field(fat, in: fatRange)
        else { return nil }
        return V1NutritionTargets(
            kcal: kcalValue.map { Int($0.rounded()) },
            proteinG: proteinValue,
            carbsG: carbsValue,
            fatG: fatValue
        )
    }

    /// `.some(nil)` for an empty field, `.some(value)` in range, nil when invalid.
    private static func field(_ text: String, in range: ClosedRange<Double>) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .some(nil) }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), range.contains(value) else {
            return nil
        }
        return .some(value)
    }

    /// `2400`, `140`, `72,5` — what a field shows for a stored target; empty when unset.
    static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return FoodPortion.editableFigure(value)
    }
}
