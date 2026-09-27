import SwiftUI

/// How the food log reads on screen: figures, the fill of a goal bar, and the tone of each
/// state. The web decides the goals, the pcts and the reading; this only formats them.
enum NutritionReadout {
    enum Macro: CaseIterable, Hashable {
        case protein, carbohydrates, fat

        var label: String {
            switch self {
            case .protein: "Protéines"
            case .carbohydrates: "Glucides"
            case .fat: "Lipides"
            }
        }

        var short: String {
            switch self {
            case .protein: "P"
            case .carbohydrates: "G"
            case .fat: "L"
            }
        }

        func line(in goals: V1NutritionGoals) -> V1NutritionMacro {
            switch self {
            case .protein: goals.protein
            case .carbohydrates: goals.carbohydrates
            case .fat: goals.fat
            }
        }

        /// One hue per macro, from the signal family, so the columns and the split read together.
        var tone: Color {
            switch self {
            case .protein: SharpitColor.signalRecovery
            case .carbohydrates: SharpitColor.signalBase
            case .fat: SharpitColor.signalTempo
            }
        }

        /// Kilocalories per gram (Atwater).
        var kcalPerGram: Double {
            self == .fat ? 9 : 4
        }

        func consumed(in day: V1NutritionDay) -> Double {
            switch self {
            case .protein: day.protein
            case .carbohydrates: day.carbohydrates
            case .fat: day.fat
            }
        }
    }

    /// `2 140` — whole kilocalories, grouped the French way.
    static func kcal(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Int(value.rounded()).formatted(.number.locale(Locale(identifier: "fr_FR")))
    }

    /// `128 g` — grams, whole.
    static func grams(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) g"
    }

    /// `1,8 g/kg` — one decimal, French separator.
    static func perKg(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))) g/kg"
    }

    /// How full a goal bar is, 0…1. Past the goal the bar is simply full; the figure says by how much.
    static func fill(pct: Double?) -> Double {
        guard let pct else { return 0 }
        return min(max(pct / 100, 0), 1)
    }

    /// What the remaining calories say: left to eat, or past the goal.
    static func remainingLabel(_ remaining: Double?) -> String? {
        guard let remaining else { return nil }
        let rounded = Int(remaining.rounded())
        if rounded >= 0 { return "Reste \(kcal(Double(rounded))) kcal" }
        return "\(kcal(Double(-rounded))) kcal au-delà"
    }

    /// Within 10 % of the goal reads as on track; further either way asks for attention.
    static func isOnGoal(pct: Double) -> Bool {
        (90...110).contains(pct)
    }

    static func goalTone(pct: Double?) -> Color {
        guard let pct else { return SharpitColor.foreground }
        return isOnGoal(pct: pct) ? SharpitColor.primary : SharpitColor.signalCaution
    }

    /// Off track is a warm « elevated » read, never the risk red: nutrition coaching does not shame.
    static func tone(for tone: V1NutritionCoachReading.Tone) -> Color {
        switch tone {
        case .onTrack: SharpitColor.primary
        case .watch: SharpitColor.signalCaution
        case .offTrack: SharpitColor.signalVo2
        }
    }

    /// The web's labels for what each finding is about (`nutrition-reading-display.ts`).
    static func jobLabel(_ job: String) -> String {
        switch job {
        case "fuel": "Carburant"
        case "quality": "Produits"
        case "diet": "Régime"
        case "weight": "Objectif de poids"
        default: "Lecture"
        }
    }

    /// Why an entry is marked, as the web words it.
    static func flagLabel(_ reason: String) -> String {
        reason == "diet_conflict" ? "Hors régime" : "Ultra-transformé"
    }

    /// Where the day's energy came from, by share of the macros' kilocalories. Empty without any.
    static func energySplit(_ day: V1NutritionDay) -> [(macro: Macro, share: Double)] {
        let kcal = Macro.allCases.map { ($0, $0.consumed(in: day) * $0.kcalPerGram) }
        let total = kcal.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        return kcal.map { (macro: $0.0, share: $0.1 / total) }
    }

    /// `72,5 kg`.
    static func kilograms(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR")))) kg"
    }

    /// `3 repas`, `1 repas`, `Aucun repas`.
    static func mealsCount(_ count: Int) -> String {
        count == 0 ? "Aucun repas" : "\(count) repas"
    }

    /// The SF Symbol for a meal, by the food log's meal key.
    static func mealSymbol(_ name: String) -> String {
        switch name.lowercased() {
        case "breakfast": "sunrise"
        case "lunch": "sun.max"
        case "dinner": "moon.stars"
        case "snacks", "snack": "leaf"
        default: "fork.knife"
        }
    }

    /// The loaded card's shape while the day loads.
    static let placeholderDay = V1NutritionDay(
        calories: 1_850, protein: 110, carbohydrates: 220, fat: 60, fiber: nil, sugar: nil,
        complete: false, goals: nil, fuelDensity: nil, meals: []
    )
}
