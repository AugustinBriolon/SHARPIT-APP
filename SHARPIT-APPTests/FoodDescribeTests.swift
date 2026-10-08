import Testing
@testable import SHARPIT_APP

@Test func foodSearchShortcutsHideOnceQueryIsSearchable() {
    #expect(!FoodSearchStore.isSearchable(""))
    #expect(!FoodSearchStore.isSearchable("a"))
    #expect(FoodSearchStore.isSearchable("riz"))
    // FoodSearchPage shows shortcuts only when `!isSearchable(query)`.
    #expect(FoodSearchStore.isSearchable("steak") == true)
}

@Test func describedFoodLineDraftScalesMacrosWithGrams() {
    let food = V1DescribedFood(
        name: "Faux-filet",
        grams: 300,
        kcal: 600,
        protein: 75,
        carbs: 0,
        fat: 30,
        per100g: V1DescribedFoodPer100g(kcal: 200, protein: 25, carbs: 0, fat: 10)
    )
    var line = DescribedFoodLine(from: food)
    line.gramsText = "150"
    let draft = try #require(line.draft(trainingDayId: "2026-10-08", meal: .lunch))
    #expect(draft.grams == 150)
    #expect(draft.meal == .lunch)
    if case .quick(let quick) = draft.source {
        #expect(quick.name == "Faux-filet")
        #expect(quick.kcal == 300)
        #expect(quick.protein == 37.5)
        #expect(quick.carbs == 0)
        #expect(quick.fat == 15)
    } else {
        Issue.record("expected quick source")
    }
}
