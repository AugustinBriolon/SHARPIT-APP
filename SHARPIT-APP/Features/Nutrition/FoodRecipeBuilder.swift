import Foundation

/// The recipe being built (SHARPIT ADR-071): its ingredients with their label, the grams typed for
/// each, the cooked weight and the servings. Its label is the web's `recipeLabel`, live; the
/// server computes the stored one the same way.
nonisolated struct FoodRecipeBuilder: Equatable, Sendable {
    struct Line: Equatable, Sendable, Identifiable {
        var ingredient: V1RecipeIngredient
        var gramsText: String

        var id: String { ingredient.productId }
    }

    static let defaultGrams = 100.0
    static let maximumIngredients = 50
    static let maximumServings = 50

    var name: String
    var lines: [Line]
    var cookedGramsText: String
    var servingsText: String

    /// A blank recipe, or the one being edited as it was saved.
    init(recipe product: V1FoodProduct? = nil) {
        name = product?.name ?? ""
        lines = product?.recipe?.ingredients.map { Line(ingredient: $0, gramsText: FoodPortion.editableFigure($0.grams)) } ?? []
        cookedGramsText = product?.recipe?.cookedGrams.map(FoodPortion.editableFigure) ?? ""
        servingsText = product?.recipe?.servings.map(String.init) ?? ""
    }

    /// A food picked again is not added twice: its line stays, the athlete changes its grams.
    mutating func add(_ product: V1FoodProduct) {
        guard !lines.contains(where: { $0.id == product.id }), lines.count < Self.maximumIngredients else { return }
        let grams = product.servingGrams ?? Self.defaultGrams
        lines.append(Line(ingredient: V1RecipeIngredient(product: product, grams: grams), gramsText: FoodPortion.editableFigure(grams)))
    }

    mutating func remove(_ productId: String) {
        lines.removeAll { $0.id == productId }
    }

    var cookedGrams: Double? { FoodLogForm.grams(cookedGramsText) }

    var servings: Int? {
        guard let value = Int(servingsText.trimmingCharacters(in: .whitespaces)),
              (1...Self.maximumServings).contains(value)
        else { return nil }
        return value
    }

    /// The label from the lines that read as a weight; nil until one does.
    var label: FoodRecipeLabel? {
        let weighed = lines.compactMap { line -> V1RecipeIngredient? in
            guard let grams = FoodLogForm.grams(line.gramsText) else { return nil }
            var ingredient = line.ingredient
            ingredient.grams = grams
            return ingredient
        }
        return FoodRecipeLabel.of(weighed, cookedGrams: cookedGrams, servings: servings)
    }

    /// What stands between the recipe and « Créer », in the athlete's words; nil when ready.
    var problem: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Donne un nom à ta recette." }
        if lines.isEmpty { return "Ajoute au moins un ingrédient." }
        if let blank = lines.first(where: { FoodLogForm.grams($0.gramsText) == nil }) {
            return "Indique les grammes de « \(blank.ingredient.name) »."
        }
        if !cookedGramsText.trimmingCharacters(in: .whitespaces).isEmpty, cookedGrams == nil {
            return "Vérifie le poids une fois cuit."
        }
        if !servingsText.trimmingCharacters(in: .whitespaces).isEmpty, servings == nil {
            return "Le nombre de parts va de 1 à \(Self.maximumServings)."
        }
        return nil
    }

    /// The recipe as the server reads it; nil while `problem` says why.
    var draft: FoodRecipeDraft? {
        guard problem == nil else { return nil }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return FoodRecipeDraft(
            name: trimmed,
            ingredients: lines.compactMap { line in
                FoodLogForm.grams(line.gramsText).map { FoodRecipeDraft.Ingredient(productId: line.id, grams: $0) }
            },
            cookedGrams: cookedGrams,
            servings: servings
        )
    }
}
