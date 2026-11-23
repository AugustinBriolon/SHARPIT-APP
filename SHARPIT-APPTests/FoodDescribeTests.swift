import Foundation
import Testing
@testable import Sharpit

@Test func foodSearchShortcutsHideOnceQueryIsSearchable() {
    #expect(!FoodSearchStore.isSearchable(""))
    #expect(!FoodSearchStore.isSearchable("a"))
    #expect(FoodSearchStore.isSearchable("riz"))
    // FoodSearchPage shows shortcuts only when `!isSearchable(query)`.
    #expect(FoodSearchStore.isSearchable("steak") == true)
}

@Test func describedFoodLineDraftScalesMacrosWithGrams() throws {
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
    #expect(line.matchCaption == "Estimation (sans note)")
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

@Test func describedFoodLineDraftUsesMatchedProduct() throws {
    let product = V1FoodProduct(
        id: "c1",
        source: "CIQUAL",
        barcode: nil,
        name: "Brocoli, cru",
        brand: nil,
        kcalPer100g: 34,
        proteinPer100g: 2.8,
        carbsPer100g: 6.6,
        fatPer100g: 0.4,
        fiberPer100g: 2.6,
        sugarPer100g: nil,
        servingGrams: nil,
        servingLabel: nil,
        health: V1FoodHealth(
            score: 88,
            scoreVersion: 2,
            grade: .excellent,
            coverage: .partial,
            nutriScore: "a",
            nutriScoreEstimated: true,
            nova: 1,
            nutrientFlags: V1FoodHealth.NutrientFlags(sugars: .low, salt: .low, saturatedFat: .low),
            additives: [],
            additivesKnown: .unknown,
            additiveCount: nil,
            highlights: [],
            dietFit: [],
            detail: .full
        )
    )
    let food = V1DescribedFood(
        name: "Brocoli, cru",
        grams: 200,
        kcal: 68,
        protein: 5.6,
        carbs: 13.2,
        fat: 0.8,
        per100g: V1DescribedFoodPer100g(kcal: 34, protein: 2.8, carbs: 6.6, fat: 0.4),
        product: product,
        match: "generic"
    )
    let line = DescribedFoodLine(from: food)
    #expect(line.matchCaption == "Table Ciqual")
    let draft = try #require(line.draft(trainingDayId: "2026-10-08", meal: .dinner))
    if case .product(let logged) = draft.source {
        #expect(logged.id == "c1")
        #expect(draft.grams == 200)
    } else {
        Issue.record("expected product source")
    }
}

@Test func describedMealTotalSumsItsFoodsAtTheGramsSet() {
    let steak = V1DescribedFood(
        name: "Faux-filet", grams: 300, kcal: 600, protein: 75, carbs: 0, fat: 30,
        per100g: V1DescribedFoodPer100g(kcal: 200, protein: 25, carbs: 0, fat: 10)
    )
    let fries = V1DescribedFood(
        name: "Frites", grams: 200, kcal: 600, protein: 6, carbs: 80, fat: 30,
        per100g: V1DescribedFoodPer100g(kcal: 300, protein: 3, carbs: 40, fat: 15)
    )
    var lines = [DescribedFoodLine(from: steak), DescribedFoodLine(from: fries)]
    #expect(DescribedMealTotal(lines).kcal == 1_200)
    #expect(DescribedMealTotal(lines).carbs == 80)
    // Halving the fries moves the meal's total; a food without a weight counts for nothing.
    lines[1].gramsText = "100"
    #expect(DescribedMealTotal(lines).kcal == 900)
    lines[0].gramsText = ""
    #expect(DescribedMealTotal(lines).kcal == 300)
    #expect(lines[1].portionCaption == "100 g · 300 kcal")
    // Neither is a known food: the dish is flagged for a look.
    #expect(DescribedMealTotal.hasEstimate(lines))
    #expect(DescribedMealTotal.foodsCaption(2) == "2 aliments")
}

private func describedFood(_ name: String, grams: Double = 100) -> V1DescribedFood {
    V1DescribedFood(
        name: name, grams: grams, kcal: grams * 2, protein: 0, carbs: 0, fat: 0,
        per100g: V1DescribedFoodPer100g(kcal: 200, protein: 0, carbs: 0, fat: 0)
    )
}

@Test func aDescribedMealComesBackDishByDish() throws {
    let json = """
    {"dishes":[
      {"name":"Œuf mayonnaise","items":[
        {"name":"Œuf dur","grams":55,"kcal":74,"protein":7,"carbs":0,"fat":5,"per100g":{"kcal":134,"protein":13,"carbs":0,"fat":9},"product":null,"match":null},
        {"name":"Mayonnaise","grams":30,"kcal":207,"protein":0,"carbs":0,"fat":23,"per100g":{"kcal":690,"protein":1,"carbs":1,"fat":76},"product":null,"match":null}]},
      {"name":"Lasagnes bolognaise","items":[
        {"name":"Lasagnes","grams":300,"kcal":402,"protein":20,"carbs":40,"fat":17,"per100g":{"kcal":134,"protein":7,"carbs":13,"fat":6},"product":null,"match":null}]}],
     "items":[]}
    """
    let dishes = try JSONDecoder().decode(V1DescribedFoodList.self, from: Data(json.utf8)).asDishes
    #expect(dishes.map(\.name) == ["Œuf mayonnaise", "Lasagnes bolognaise"])
    #expect(dishes.map(\.items.count) == [2, 1])
}

/// A server that does not tell dishes apart answers the foods flat: one dish, named by the
/// athlete's own words.
@Test func foodsAnsweredFlatReadAsOneDishNamedByTheDescription() throws {
    let json = """
    {"items":[{"name":"Pizza","grams":300,"kcal":810,"protein":30,"carbs":90,"fat":30,"per100g":{"kcal":270,"protein":10,"carbs":30,"fat":10},"product":null,"match":null}]}
    """
    let dishes = try JSONDecoder().decode(V1DescribedFoodList.self, from: Data(json.utf8)).asDishes
    #expect(dishes.count == 1)
    #expect(DescribedDish(from: dishes[0], fallbackName: "pizza du midi").name == "Pizza du midi")
}

@Test func eachDishIsLoggedUnderItsOwnNameWithOnlyItsFoods() throws {
    var starter = DescribedDish(from: V1DescribedDish(name: "œuf mayonnaise", items: [describedFood("Œuf dur", grams: 55), describedFood("Mayonnaise", grams: 30)]))
    #expect(starter.name == "Œuf mayonnaise")
    let logged = try #require(starter.drafts(trainingDayId: "2026-11-23", meal: .lunch))
    #expect(logged.name == "Œuf mayonnaise")
    #expect(logged.drafts.map(\.grams) == [55, 30])
    #expect(logged.drafts.allSatisfy { $0.meal == .lunch })

    // A food without a weight is left out; a dish with none left is not logged at all.
    starter.lines[1].gramsText = ""
    #expect(starter.drafts(trainingDayId: "2026-11-23", meal: .lunch)?.drafts.count == 1)
    starter.lines[0].gramsText = ""
    #expect(starter.drafts(trainingDayId: "2026-11-23", meal: .lunch) == nil)

    // A name wiped leaves the foods on their own, ungrouped.
    var dessert = DescribedDish(from: V1DescribedDish(name: "Mousse au chocolat", items: [describedFood("Mousse au chocolat")]))
    dessert.name = "  "
    #expect(dessert.drafts(trainingDayId: "2026-11-23", meal: .lunch)?.name == nil)
    #expect(DescribedMealTotal.dishesCaption(1) == "1 plat")
    #expect(DescribedMealTotal.dishesCaption(3) == "3 plats")
}
