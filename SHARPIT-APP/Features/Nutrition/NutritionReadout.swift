import SwiftUI

/// How the food log reads on screen: figures, the fill of a goal bar, and the tone of each
/// state. The web decides the goals, the pcts and the reading; this only formats them.
enum NutritionReadout {
    enum Macro: CaseIterable, Hashable {
        case protein, carbohydrates, fat

        /// The shared name and hue, so the app and its widgets read a macro alike.
        var kind: WidgetSnapshot.Macro.Kind {
            switch self {
            case .protein: .protein
            case .carbohydrates: .carbohydrates
            case .fat: .fat
            }
        }

        var label: String { kind.label }

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
        var tone: Color { kind.tone }

        /// Kilocalories per gram (Atwater).
        var kcalPerGram: Double {
            switch self {
            case .protein: NutritionTargetSplit.proteinKcalPerGram
            case .carbohydrates: NutritionTargetSplit.carbsKcalPerGram
            case .fat: NutritionTargetSplit.fatKcalPerGram
            }
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
        SharpitFigureFormat.kcal(value)
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
        SharpitFigureFormat.remainingKcal(remaining)
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
        energySplit(protein: day.protein, carbohydrates: day.carbohydrates, fat: day.fat)
    }

    /// Where a food's or a day's energy comes from, by macro (Atwater); empty without energy.
    static func energySplit(protein: Double, carbohydrates: Double, fat: Double) -> [(macro: Macro, share: Double)] {
        let grams: [Macro: Double] = [.protein: protein, .carbohydrates: carbohydrates, .fat: fat]
        let kcal = Macro.allCases.map { ($0, max(grams[$0] ?? 0, 0) * $0.kcalPerGram) }
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

    /// The page's shape while a day loads.
    static var placeholderResponse: V1NutritionResponse {
        let line = V1NutritionMacro(consumed: 1_850, goal: 2_400, remaining: 550, pct: 77)
        let macro = V1NutritionMacro(consumed: 100, goal: 140, remaining: 40, pct: 71)
        return V1NutritionResponse(
            trainingDayId: TrainingDayId.today(now: .now),
            day: V1NutritionDay(
                calories: 1_850, protein: 100, carbohydrates: 220, fat: 60, fiber: nil, sugar: nil,
                complete: false,
                goals: V1NutritionGoals(calories: line, protein: macro, carbohydrates: macro, fat: macro, exerciseCalories: 300, calorieBudget: 2_700),
                fuelDensity: nil,
                meals: [
                    V1NutritionMeal(name: "breakfast", label: "Petit-déjeuner", calories: 520, protein: 25, carbs: 70, fat: 14, entries: []),
                    V1NutritionMeal(name: "lunch", label: "Déjeuner", calories: 780, protein: 40, carbs: 90, fat: 25, entries: []),
                ]
            )
        )
    }
}
