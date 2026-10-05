import Foundation

// What a MyFitnessPal athlete logs with in one tap (SHARPIT ADR-071): a meal copied from another
// day, a meal kept under a name, a recipe made of other foods.

/// One ingredient of a recipe, with its label so the recipe can be edited and previewed.
nonisolated struct V1RecipeIngredient: Codable, Sendable, Equatable, Hashable, Identifiable {
    let productId: String
    var name: String
    var brand: String?
    var grams: Double
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double? = nil
    var sugarPer100g: Double? = nil
    var saltPer100g: Double? = nil
    var saturatedFatPer100g: Double? = nil

    var id: String { productId }

    init(product: V1FoodProduct, grams: Double) {
        productId = product.id
        name = product.name
        brand = product.brand
        self.grams = grams
        kcalPer100g = product.kcalPer100g
        proteinPer100g = product.proteinPer100g
        carbsPer100g = product.carbsPer100g
        fatPer100g = product.fatPer100g
        fiberPer100g = product.fiberPer100g
        sugarPer100g = product.sugarPer100g
        saltPer100g = product.saltPer100g
        saturatedFatPer100g = product.saturatedFatPer100g
    }
}

nonisolated struct V1Recipe: Codable, Sendable, Equatable, Hashable {
    var ingredients: [V1RecipeIngredient]
    var cookedGrams: Double?
    var servings: Int?
    var totalGrams: Double
}

/// One food of a saved meal, as it was logged.
nonisolated struct V1SavedMealItem: Codable, Sendable, Equatable, Hashable {
    var productId: String?
    var name: String
    var brand: String?
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
}

/// A meal kept under a name, with its totals and its score (SHARPIT ADR-070).
nonisolated struct V1SavedMeal: Codable, Sendable, Equatable, Hashable, Identifiable {
    let id: String
    var name: String
    var items: [V1SavedMealItem]
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var health: V1MealHealth?
}

/// `GET /api/v1/food-log/meals`, last used first.
nonisolated struct V1SavedMealList: Decodable, Sendable, Equatable {
    let meals: [V1SavedMeal]
}

nonisolated struct V1SavedMealEnvelope: Decodable, Sendable {
    let meal: V1SavedMeal
}

/// `POST /api/v1/food-log/copy` and `POST /api/v1/food-log/meals/<id>/log`: the entries written.
nonisolated struct V1FoodLogEntryList: Decodable, Sendable, Equatable {
    let entries: [V1FoodLogEntry]
}

/// A recipe as the athlete sends it: the ingredients weighed raw, the cooked weight and servings
/// optional.
nonisolated struct FoodRecipeDraft: Sendable, Equatable {
    struct Ingredient: Sendable, Equatable {
        var productId: String
        var grams: Double
    }

    var name: String
    var ingredients: [Ingredient]
    var cookedGrams: Double?
    var servings: Int?
}

/// A recipe's label per 100 g, the web's `recipeLabel`: the ingredients summed over the dish's
/// weight, cooked when weighed. A line one ingredient does not give stays unknown.
nonisolated struct FoodRecipeLabel: Equatable, Sendable {
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double?
    var totalGrams: Double
    var servingGrams: Double?

    static func of(
        _ ingredients: [V1RecipeIngredient], cookedGrams: Double? = nil, servings: Int? = nil
    ) -> FoodRecipeLabel? {
        let rawGrams = ingredients.reduce(0) { $0 + $1.grams }
        let total = cookedGrams.flatMap { $0 > 0 ? $0 : nil } ?? rawGrams
        guard !ingredients.isEmpty, total > 0 else { return nil }
        func per100g(_ pick: (V1RecipeIngredient) -> Double) -> Double {
            round1(ingredients.reduce(0) { $0 + pick($1) * $1.grams / 100 } * 100 / total)
        }
        let fiberKnown = ingredients.allSatisfy { $0.fiberPer100g != nil }
        return FoodRecipeLabel(
            kcalPer100g: per100g(\.kcalPer100g),
            proteinPer100g: per100g(\.proteinPer100g),
            carbsPer100g: per100g(\.carbsPer100g),
            fatPer100g: per100g(\.fatPer100g),
            fiberPer100g: fiberKnown ? per100g { $0.fiberPer100g ?? 0 } : nil,
            totalGrams: round1(total),
            servingGrams: servings.flatMap { $0 > 0 ? round1(total / Double($0)) : nil }
        )
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

nonisolated extension TrainingDayId {
    /// The training day before `trainingDayId`, read on the calendar; nil for a malformed id.
    static func previous(_ trainingDayId: String) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: trainingDayId),
              let before = calendar.date(byAdding: .day, value: -1, to: date)
        else { return nil }
        return parser.string(from: before)
    }
}

nonisolated enum SavedMealNaming {
    /// What a saved meal is called until the athlete names it: its foods, heaviest first.
    static func defaultName(_ entries: [V1FoodLogEntry]) -> String {
        let names = entries.sorted { $0.kcal > $1.kcal }.map(\.name)
        let joined = names.prefix(3).joined(separator: ", ")
        let name = names.count > 3 ? "\(joined)…" : joined
        return name.count > 80 ? "\(name.prefix(79))…" : name
    }
}
