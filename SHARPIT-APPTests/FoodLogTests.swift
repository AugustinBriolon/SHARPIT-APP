import Foundation
import Testing
@testable import Sharpit

// MARK: - Payloads

private let dayJSON = """
{
  "trainingDayId": "2026-10-01",
  "entries": [
    { "id": "e2", "athleteId": "a1", "date": "2026-10-01T00:00:00.000Z", "meal": "LUNCH", "productId": "p1",
      "name": "Riz basmati", "brand": "Taureau Ailé", "grams": 150, "kcal": 525, "protein": 11.3, "carbs": 115.5,
      "fat": 1.5, "fiber": null, "sugar": 0.3, "createdAt": "2026-10-01T12:10:00.000Z", "updatedAt": "2026-10-01T12:10:00.000Z" },
    { "id": "e1", "athleteId": "a1", "date": "2026-10-01T00:00:00.000Z", "meal": "BREAKFAST", "productId": null,
      "name": "Café au lait", "brand": null, "grams": 100, "kcal": 60, "protein": 3, "carbs": 5, "fat": 3,
      "createdAt": "2026-10-01T07:00:00.000Z", "updatedAt": "2026-10-01T07:00:00.000Z" },
    { "id": "e3", "athleteId": "a1", "date": "2026-10-01T00:00:00.000Z", "meal": "SNACKS", "name": "Banane",
      "grams": 120, "kcal": 107, "protein": 1.3, "carbs": 27.6, "fat": 0.4,
      "createdAt": "2026-10-01T16:00:00.000Z", "updatedAt": "2026-10-01T16:00:00.000Z" }
  ],
  "targets": { "kcal": 2400, "proteinG": 140, "carbsG": null, "fatG": 80.5 },
  "recent": [
    { "product": { "id": "p1", "source": "OFF", "barcode": "3017620422003", "ownerId": null, "name": "Riz basmati",
        "brand": "Taureau Ailé", "kcalPer100g": 350, "proteinPer100g": 7.5, "carbsPer100g": 77, "fatPer100g": 1,
        "fiberPer100g": null, "sugarPer100g": 0.2, "servingGrams": 75, "servingLabel": "1 portion",
        "fetchedAt": "2026-09-30T10:00:00.000Z", "createdAt": "2026-09-30T10:00:00.000Z", "updatedAt": "2026-09-30T10:00:00.000Z" },
      "lastGrams": 150 }
  ]
}
"""

@Test func theFoodLogDayDecodesItsEntriesTargetsAndRecentFoods() throws {
    let day = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))

    #expect(day.entries.map(\.id) == ["e2", "e1", "e3"])
    #expect(day.entries[0].meal == .lunch)
    #expect(day.entries[0].brand == "Taureau Ailé")
    #expect(day.entries[1].productId == nil)
    #expect(day.entries[2].fiber == nil)
    #expect(day.targets == V1NutritionTargets(kcal: 2400, proteinG: 140, carbsG: nil, fatG: 80.5))
    let recent = try #require(day.recent.first)
    #expect(recent.lastGrams == 150)
    #expect(recent.product.isOpenFoodFacts)
    #expect(recent.product.servingLabel == "1 portion")
}

@Test func searchResultsAndAScannedProductDecode() throws {
    let search = try JSONDecoder().decode(V1FoodSearchResults.self, from: Data("""
    { "own": [{ "id": "c1", "source": "CUSTOM", "ownerId": "a1", "name": "Granola maison", "kcalPer100g": 450,
                "proteinPer100g": 12, "carbsPer100g": 55, "fatPer100g": 18 }],
      "products": [], "offUnavailable": true }
    """.utf8))
    #expect(search.own.first?.source == "CUSTOM")
    #expect(search.own.first?.isOpenFoodFacts == false)
    #expect(search.offUnavailable)

    let product = try JSONDecoder().decode(V1FoodProductEnvelope.self, from: Data("""
    { "product": { "id": "p9", "source": "OFF", "barcode": "3274080005003", "name": "Eau minérale", "brand": null,
                   "kcalPer100g": 0, "proteinPer100g": 0, "carbsPer100g": 0, "fatPer100g": 0 } }
    """.utf8)).product
    #expect(product.barcode == "3274080005003")
    #expect(product.servingGrams == nil)
    #expect(product.health == nil)

    let scored = try JSONDecoder().decode(V1FoodProduct.self, from: Data("""
    { "id": "p10", "source": "OFF", "barcode": "3017620422003", "name": "Nutella",
      "kcalPer100g": 539, "proteinPer100g": 6.3, "carbsPer100g": 57.5, "fatPer100g": 30.9,
      "health": {
        "score": 18, "scoreVersion": 1, "grade": "poor", "coverage": "full",
        "nutriScore": "e", "nova": 4,
        "nutrientFlags": { "sugars": "high", "salt": "low", "saturatedFat": "high" },
        "additives": [{ "code": "E322", "name": "Lécithines", "risk": "none" }]
      } }
    """.utf8))
    #expect(scored.health?.score == 18)
    #expect(scored.health?.grade == .poor)
    #expect(scored.health?.nutrientFlags.sugars == .high)
    #expect(scored.health?.additives.first?.code == "E322")
    // A score stored before version 2 reads with nothing to explain.
    #expect(scored.health?.highlights == [])
    #expect(scored.health?.dietFit == [])
    #expect(scored.health?.detail == .full)
    #expect(scored.health?.additivesKnown == .list)
}

private let scoredV2JSON = """
{ "score": 31, "scoreVersion": 2, "grade": "mediocre", "coverage": "full",
  "nutriScore": "c", "nutriScoreEstimated": true, "nova": 4,
  "nutrientFlags": { "sugars": "high", "salt": "low", "saturatedFat": "low" },
  "additives": [], "additivesKnown": "count", "additiveCount": 2,
  "highlights": [
    { "key": "sports_nutrition", "tone": "neutral", "label": "Produit d’effort", "detail": "Sucres rapides voulus" },
    { "key": "sugars_high", "tone": "negative", "label": "Trop sucré", "detail": "40 g/100 g" },
    { "key": "protein_rich", "tone": "positive", "label": "Riche en protéines", "detail": "21 g/100 g" }
  ],
  "dietFit": [
    { "diet": "vegan", "label": "Végétalien", "status": "incompatible", "reason": "Contient des ingrédients non végétaliens" },
    { "diet": "keto", "label": "Cétogène", "status": "uncertain", "reason": "8 g de glucides/100 g — à doser" }
  ],
  "detail": "summary" }
"""

@Test func aVersionTwoScoreCarriesItsReasonsAndDiets() throws {
    let health = try JSONDecoder().decode(V1FoodHealth.self, from: Data(scoredV2JSON.utf8))
    #expect(health.detail == .summary)
    #expect(health.additivesKnown == .count)
    #expect(health.nutriScoreEstimated)
    #expect(health.watchPoints.map(\.key) == ["sugars_high"])
    #expect(health.strengths.map(\.key) == ["protein_rich"])
    #expect(health.notes.map(\.key) == ["sports_nutrition"])
    #expect(health.incompatibleDiets.map(\.label) == ["Végétalien"])
}

@Test func searchResultsCarryGenericFoodsAndNameTheirSources() throws {
    let json = """
    { "own": [],
      "generic": [{ "id": "g1", "source": "CIQUAL", "name": "Banane, pulpe, crue",
                    "kcalPer100g": 90.5, "proteinPer100g": 1.06, "carbsPer100g": 19.7, "fatPer100g": 0.25 }],
      "products": [{ "id": "p1", "source": "OFF", "barcode": "3017620422003", "name": "Nectar de banane",
                     "kcalPer100g": 60, "proteinPer100g": 0.3, "carbsPer100g": 14, "fatPer100g": 0 }],
      "offUnavailable": false }
    """
    let results = try JSONDecoder().decode(V1FoodSearchResults.self, from: Data(json.utf8))
    #expect(results.generic.first?.isCiqual == true)
    #expect(!results.isEmpty)
    #expect(V1FoodProduct.attribution(for: results.generic) == "Table Ciqual 2020, Anses (Licence Ouverte)")
    #expect(V1FoodProduct.attribution(for: results.generic + results.products)
        == "Table Ciqual 2020, Anses (Licence Ouverte) · Données Open Food Facts (ODbL)")
    #expect(V1FoodProduct.attribution(for: []) == nil)

    let older = try JSONDecoder().decode(
        V1FoodSearchResults.self,
        from: Data(#"{ "own": [], "products": [], "offUnavailable": true }"#.utf8)
    )
    #expect(older.generic.isEmpty)
    #expect(older.isEmpty)
}

@Test func searchResultsListTheFoodsAlreadyEatenAndTheVerifiedOnes() throws {
    let json = """
    { "eaten": [{ "product": { "id": "e1", "source": "OFF", "barcode": "5690845000621", "name": "Skyr",
                               "kcalPer100g": 62, "proteinPer100g": 11, "carbsPer100g": 4, "fatPer100g": 0.2,
                               "verified": true, "verifiedBy": "producer" },
                  "timesEaten": 12, "lastGrams": 150 }],
      "own": [], "generic": [], "products": [], "offUnavailable": false }
    """
    let results = try JSONDecoder().decode(V1FoodSearchResults.self, from: Data(json.utf8))
    let eaten = try #require(results.eaten.first)
    #expect(eaten.timesEaten == 12)
    #expect(eaten.lastGrams == 150)
    #expect(eaten.product.isVerified)
    #expect(eaten.product.verifiedLabel == "Vérifié, données du fabricant")
    #expect(!results.isEmpty)

    let older = try JSONDecoder().decode(
        V1FoodSearchResults.self,
        from: Data(#"{ "own": [], "products": [], "offUnavailable": false }"#.utf8)
    )
    #expect(older.eaten.isEmpty)
}

@Test func aFoodWithoutTheFieldIsNotVerified() throws {
    let product = try JSONDecoder().decode(V1FoodProduct.self, from: Data(#"""
    { "id": "c1", "source": "CUSTOM", "name": "Granola maison",
      "kcalPer100g": 450, "proteinPer100g": 10, "carbsPer100g": 60, "fatPer100g": 18 }
    """#.utf8))
    #expect(!product.isVerified)
    #expect(product.verifiedLabel == nil)
}

@Test func theScoreReadsInWords() throws {
    let health = try JSONDecoder().decode(V1FoodHealth.self, from: Data(scoredV2JSON.utf8))
    #expect(FoodHealthPresentation.verdict(health) == "1 point à surveiller\n1 point fort")
    #expect(FoodHealthPresentation.sources(health) == "Nutri-Score C (estimé) · NOVA 4")
    #expect(FoodHealthPresentation.additiveStatus(health, isCompleting: true) == "2 additifs, lecture du détail…")
    #expect(FoodHealthPresentation.additiveStatus(health, isCompleting: false) == "2 additifs, détail indisponible")
    #expect(FoodHealthPresentation.symbol(for: health.watchPoints[0]) == "cube")
    #expect(FoodHealthPresentation.symbol(for: .init(key: "mystery", tone: .positive, label: "?", detail: nil)) == "checkmark.circle")

    var quiet = health
    quiet.highlights = []
    quiet.nutriScore = nil
    quiet.nova = nil
    quiet.additivesKnown = .list
    #expect(FoodHealthPresentation.verdict(quiet) == "Rien de marquant dans sa composition")
    #expect(FoodHealthPresentation.sources(quiet) == nil)
    #expect(FoodHealthPresentation.additiveStatus(quiet, isCompleting: false) == nil)
}

@Test func anUnknownMealKeyReadsAsASnack() throws {
    let entry = try JSONDecoder().decode(V1FoodLogEntry.self, from: Data("""
    { "id": "e", "meal": "BRUNCH", "name": "x", "grams": 1, "kcal": 1, "protein": 0, "carbs": 0, "fat": 0 }
    """.utf8))
    #expect(entry.meal == .snacks)
}

@Test func theNutritionDayDecodesWithOrWithoutTheRetiredMyFitnessPalFlag() throws {
    let json = { (extra: String) in
        """
        { "apiVersion": 1, "trainingDayId": "2026-10-01", "connected": true, \(extra) "empty": null, "day": null,
          "coachReading": null, "diet": [], "history": [] }
        """
    }
    // The app no longer reads `mfpConnected` (docs/adr/0010); a server still sending it must not cost the day.
    #expect(try JSONDecoder().decode(V1NutritionResponse.self, from: Data(json("\"mfpConnected\": true,").utf8)).connected)
    #expect(try JSONDecoder().decode(V1NutritionResponse.self, from: Data(json("").utf8)).connected)
}

// MARK: - Targets payload

@Test func targetsInPercentDecodeTheirModeAndShares() throws {
    let targets = try JSONDecoder().decode(V1NutritionTargetsEnvelope.self, from: Data("""
    { "targets": { "mode": "PERCENT", "kcal": 2400, "proteinG": 150, "carbsG": 270, "fatG": 80,
                   "proteinPct": 25, "carbsPct": 45, "fatPct": 30 } }
    """.utf8)).targets
    #expect(targets == V1NutritionTargets(
        mode: .percent, kcal: 2400, proteinG: 150, carbsG: 270, fatG: 80, proteinPct: 25, carbsPct: 45, fatPct: 30
    ))
}

@Test func targetsFromAnOlderServerReadAsGrams() throws {
    let older = try JSONDecoder().decode(V1NutritionTargets.self, from: Data("""
    { "kcal": 2400.0, "proteinG": 140, "carbsG": null, "fatG": 80.5 }
    """.utf8))
    #expect(older.mode == .grams)
    #expect(older.kcal == 2400)
    #expect(older.proteinPct == nil && older.carbsPct == nil && older.fatPct == nil)

    let unknownMode = try JSONDecoder().decode(V1NutritionTargets.self, from: Data("""
    { "mode": "RATIO", "kcal": null, "proteinG": null, "carbsG": null, "fatG": null, "proteinPct": 30.0 }
    """.utf8))
    #expect(unknownMode.mode == .grams)
    #expect(unknownMode.proteinPct == 30)
}

// MARK: - Own foods and import payloads

@Test func ownFoodsDecode() throws {
    let list = try JSONDecoder().decode(V1FoodProductList.self, from: Data("""
    { "foods": [
        { "id": "c2", "source": "CUSTOM", "ownerId": "a1", "name": "Pâte à tartiner maison", "brand": null,
          "kcalPer100g": 520, "proteinPer100g": 6, "carbsPer100g": 55, "fatPer100g": 30, "servingGrams": 15 },
        { "id": "c1", "source": "CUSTOM", "ownerId": "a1", "name": "Granola maison", "kcalPer100g": 450,
          "proteinPer100g": 12, "carbsPer100g": 55, "fatPer100g": 18 } ] }
    """.utf8))
    #expect(list.foods.map(\.id) == ["c2", "c1"])
    #expect(list.foods.allSatisfy { !$0.isOpenFoodFacts })
    #expect(list.foods[0].servingGrams == 15)
    #expect(OwnFoodsStore.sorted(list.foods).map(\.name) == ["Granola maison", "Pâte à tartiner maison"])
    #expect(try JSONDecoder().decode(V1FoodProductList.self, from: Data(#"{ "foods": [] }"#.utf8)).foods.isEmpty)
}

@Test func aFoodLogRefusalReadsTheServersMessage() {
    #expect(FoodLogClient.refusal(in: Data(#"{ "error": " Fichier illisible. " }"#.utf8)) == "Fichier illisible.")
    #expect(FoodLogClient.refusal(in: Data("<html>".utf8)) == nil)
}

// MARK: - Request bodies

private nonisolated let rice = V1FoodProduct(
    id: "p1", source: "OFF", barcode: "3017620422003", name: "Riz basmati", brand: "Taureau Ailé",
    kcalPer100g: 350, proteinPer100g: 7.5, carbsPer100g: 77, fatPer100g: 1,
    fiberPer100g: nil, sugarPer100g: 0.2, servingGrams: 75, servingLabel: "1 portion"
)

private func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func aProductEntryCarriesItsIdAndNoQuickAdd() throws {
    let body = try object(FoodLogClient.body(for: FoodLogDraft(
        trainingDayId: "2026-10-01", meal: .lunch, grams: 150, source: .product(rice)
    )))
    #expect(body["trainingDayId"] as? String == "2026-10-01")
    #expect(body["meal"] as? String == "LUNCH")
    #expect(body["grams"] as? Double == 150)
    #expect(body["productId"] as? String == "p1")
    #expect(body["quick"] == nil)
}

@Test func aQuickAddCarriesItsFiguresAndNoProduct() throws {
    let body = try object(FoodLogClient.body(for: FoodLogDraft(
        trainingDayId: "2026-10-01", meal: .dinner, grams: 100,
        source: .quick(FoodQuickAdd(name: "Pizza", kcal: 800, protein: 30, carbs: nil, fat: nil))
    )))
    #expect(body["productId"] == nil)
    let quick = try #require(body["quick"] as? [String: Any])
    #expect(quick["name"] as? String == "Pizza")
    #expect(quick["kcal"] as? Double == 800)
    #expect(quick["protein"] as? Double == 30)
    // The server defaults a missing macro to 0; sending 0 says the same without a null it refuses.
    #expect(quick["carbs"] as? Double == 0)
}

@Test func anEntryChangeSendsOnlyWhatChanged() throws {
    let grams = try object(FoodLogClient.body(for: FoodLogEntryChange(grams: 80, meal: nil)))
    #expect(grams["grams"] as? Double == 80)
    #expect(grams["meal"] == nil)

    let meal = try object(FoodLogClient.body(for: FoodLogEntryChange(grams: nil, meal: .snacks)))
    #expect(meal.keys.sorted() == ["meal"])
}

@Test func clearedTargetsGoOutAsNull() throws {
    let body = try object(FoodLogClient.body(for: V1NutritionTargets(kcal: 2200, proteinG: nil, carbsG: 280, fatG: nil)))
    #expect(body["mode"] as? String == "GRAMS")
    #expect(body["kcal"] as? Int == 2200)
    #expect(body["proteinG"] is NSNull)
    #expect(body["carbsG"] as? Double == 280)
    #expect(body["fatG"] is NSNull)
    #expect(body["proteinPct"] == nil)
}

@Test func targetsInPercentSendTheEnergyAndTheSharesOnly() throws {
    let split = try #require(NutritionTargetSplit(kcal: "2400", protein: "25", carbs: "45", fat: "30").targets)
    let body = try object(FoodLogClient.body(for: split))
    #expect(body.keys.sorted() == ["carbsPct", "fatPct", "kcal", "mode", "proteinPct"])
    #expect(body["mode"] as? String == "PERCENT")
    #expect(body["kcal"] as? Int == 2400)
    #expect(body["proteinPct"] as? Int == 25)
    #expect(body["carbsPct"] as? Int == 45)
    #expect(body["fatPct"] as? Int == 30)
}

@Test func anEditedOwnFoodSendsEveryField() throws {
    let granola = V1FoodProduct(
        id: "c1", source: "CUSTOM", barcode: nil, name: "Granola", brand: "Maison",
        kcalPer100g: 450, proteinPer100g: 12, carbsPer100g: 55, fatPer100g: 18,
        fiberPer100g: nil, sugarPer100g: 20, servingGrams: 40, servingLabel: nil
    )
    let body = try object(FoodLogClient.body(for: FoodCustomDraft(product: granola)))
    #expect(body["name"] as? String == "Granola")
    #expect(body["brand"] as? String == "Maison")
    #expect(body["fiberPer100g"] is NSNull)
    #expect(body["sugarPer100g"] as? Double == 20)
    #expect(body["saltPer100g"] is NSNull)
    #expect(body["servingGrams"] as? Double == 40)
}

@Test func aCustomFoodSendsItsMissingOptionsAsNull() throws {
    let body = try object(FoodLogClient.body(for: FoodCustomDraft(
        name: "Granola", brand: nil, kcalPer100g: 450, proteinPer100g: 12, carbsPer100g: 55, fatPer100g: 18,
        fiberPer100g: 8, sugarPer100g: nil, saltPer100g: 0.5, saturatedFatPer100g: nil, servingGrams: nil
    )))
    #expect(body["brand"] is NSNull)
    #expect(body["fiberPer100g"] as? Double == 8)
    #expect(body["sugarPer100g"] is NSNull)
    #expect(body["saltPer100g"] as? Double == 0.5)
    #expect(body["saturatedFatPer100g"] is NSNull)
    #expect(body["servingGrams"] is NSNull)
}

@Test func statusesMapToWhatTheScreenSays() {
    #expect(throws: FoodLogError.notFound) { try FoodLogClient.check(status: 404) }
    #expect(throws: SharpitAPIError.rateLimited) { try FoodLogClient.check(status: 429) }
    #expect(throws: FoodLogError.openFoodFactsUnavailable) { try FoodLogClient.check(status: 503) }
    #expect(throws: SharpitAPIError.badRequest) { try FoodLogClient.check(status: 400) }
    #expect(throws: SharpitAPIError.unauthorized) { try FoodLogClient.check(status: 401) }
    #expect(throws: SharpitAPIError.server) { try FoodLogClient.check(status: 500) }
    #expect(throws: Never.self) { try FoodLogClient.check(status: 204) }
}

// MARK: - Portion

@Test func aPortionScalesPer100GramsToOneDecimal() {
    let portion = FoodPortion.nutrients(of: rice, grams: 155)
    #expect(portion.kcal == 542.5)
    #expect(portion.protein == 11.6)
    #expect(portion.carbs == 119.4)
    #expect(portion.fat == 1.6)
    #expect(FoodPortion.nutrients(of: rice, grams: 0).kcal == 0)
}

@Test func aLoggedEntryRescalesByItsWeight() {
    let entry = V1FoodLogEntry(
        id: "e", meal: .lunch, productId: nil, name: "Pâtes", brand: nil, grams: 200,
        kcal: 300, protein: 10, carbs: 60, fat: 1.5
    )
    let half = FoodPortion.nutrients(of: entry, grams: 100)
    #expect(half == FoodPortion.Nutrients(kcal: 150, protein: 5, carbs: 30, fat: 0.8))
}

@Test func thePresetsOfferTheServingAndTheLastWeightOnce() {
    let presets = FoodPortion.presets(for: rice, lastGrams: 150)
    #expect(presets.map(\.grams) == [100, 75, 150])
    #expect(presets[1].label == "1 portion · 75 g")
    #expect(FoodPortion.presets(for: rice, lastGrams: 100).map(\.grams) == [100, 75])
    #expect(FoodPortion.initialGrams(for: rice, lastGrams: nil) == 75)
    #expect(FoodPortion.initialGrams(for: rice, lastGrams: 150) == 150)
}

@Test func onlyFoodBarcodesAreLookedUp() {
    #expect(FoodBarcode.normalized("3017620422003") == "3017620422003")
    #expect(FoodBarcode.normalized(" 12345670 ") == "12345670")
    #expect(FoodBarcode.normalized("https://example.com") == nil)
    #expect(FoodBarcode.normalized("12345") == nil)
    #expect(FoodBarcode.normalized(nil) == nil)
}

@Test func targetsParseFrenchNumbersAndRefuseOutOfRange() {
    #expect(NutritionTargetsInput.parse(kcal: "2400", protein: "140,5", carbs: "", fat: " ")
        == V1NutritionTargets(kcal: 2400, proteinG: 140.5, carbsG: nil, fatG: nil))
    #expect(NutritionTargetsInput.parse(kcal: "500", protein: "", carbs: "", fat: "") == nil)
    #expect(NutritionTargetsInput.parse(kcal: "", protein: "abc", carbs: "", fat: "") == nil)
    #expect(NutritionTargetsInput.parse(kcal: "", protein: "", carbs: "", fat: "") == V1NutritionTargets.none)
    #expect(NutritionTargetsInput.text(2400) == "2400")
}

// MARK: - Targets split

@Test func percentagesBecomeTheServersGrams() throws {
    let split = NutritionTargetSplit(kcal: "2400", protein: "25", carbs: "45", fat: "30")
    #expect(split.total == 100)
    #expect(split.isBalanced)
    // round(2400 × 25 / 100 / 4) = 150, round(2400 × 45 / 100 / 4) = 270, round(2400 × 30 / 100 / 9) = 80.
    #expect([split.proteinG, split.carbsG, split.fatG] == [150, 270, 80])
    let targets = try #require(split.targets)
    #expect(targets.mode == .percent)
    #expect(targets.proteinG == 150 && targets.carbsG == 270 && targets.fatG == 80)
    #expect(NutritionTargetSplit.grams(kcal: 2150, pct: 33, kcalPerGram: 9) == 79)
}

@Test func aSplitIsRefusedUnlessTheEnergyIsSetAndTheSharesMakeAHundred() {
    let short = NutritionTargetSplit(kcal: "2400", protein: "25", carbs: "45", fat: "")
    #expect(short.total == 70)
    #expect(!short.isBalanced)
    #expect(short.targets == nil)
    #expect(short.fatG == nil)

    #expect(NutritionTargetSplit(kcal: "", protein: "25", carbs: "45", fat: "30").targets == nil)
    #expect(NutritionTargetSplit(kcal: "", protein: "25", carbs: "45", fat: "30").proteinG == nil)
    #expect(NutritionTargetSplit(kcal: "500", protein: "25", carbs: "45", fat: "30").targets == nil)
    #expect(NutritionTargetSplit(kcal: "2400", protein: "30", carbs: "45", fat: "30").targets == nil)

    let decimal = NutritionTargetSplit(kcal: "2400", protein: "25,5", carbs: "45", fat: "30")
    #expect(decimal.hasInvalidShare)
    #expect(decimal.targets == nil)
    #expect(NutritionTargetSplit(kcal: "2400", protein: "120", carbs: "0", fat: "0").hasInvalidShare)
    #expect(NutritionTargetSplit(kcal: "2400", protein: "100", carbs: "0", fat: "0").targets != nil)
}

@Test func gramsSwitchedToPercentGiveSharesThatMakeAHundred() throws {
    // 150 g × 4 = 600 kcal (25 %), 270 g × 4 = 1080 (45 %), 80 g × 9 = 720 (30 %).
    let exact = try #require(NutritionTargetSplit.fromGramsForm(kcal: "2400", protein: "150", carbs: "270", fat: "80"))
    #expect([exact.proteinPct, exact.carbsPct, exact.fatPct] == [25, 45, 30])

    // 140 g → 23,3 %, 280 g → 46,7 %, 80 g → 30 %: rounded to a total of exactly 100.
    let rounded = try #require(NutritionTargetSplit.fromGramsForm(kcal: "2400", protein: "140", carbs: "280", fat: "80"))
    #expect([rounded.proteinPct, rounded.carbsPct, rounded.fatPct] == [23, 47, 30])
    #expect(rounded.total == 100)

    // Grams that do not fill the energy keep their own shares: the total says they are off.
    let partial = try #require(NutritionTargetSplit.fromGramsForm(kcal: "2400", protein: "150", carbs: "", fat: "80"))
    #expect([partial.proteinPct, partial.carbsPct, partial.fatPct] == [25, nil, 30])
    #expect(!partial.isBalanced)

    #expect(NutritionTargetSplit.fromGramsForm(kcal: "", protein: "150", carbs: "270", fat: "80") == nil)
    #expect(NutritionTargetSplit.fromGramsForm(kcal: "2400", protein: "", carbs: "", fat: "") == nil)
}

@Test func theTargetsSheetOpensOnTheStoredMode() {
    let percent = V1NutritionTargets(
        mode: .percent, kcal: 2400, proteinG: 150, carbsG: 270, fatG: 80, proteinPct: 25, carbsPct: 45, fatPct: 30
    )
    #expect(NutritionTargetSplit.prefill(from: percent) == NutritionTargetSplit(kcal: 2400, proteinPct: 25, carbsPct: 45, fatPct: 30))

    let grams = V1NutritionTargets(kcal: 2400, proteinG: 150, carbsG: 270, fatG: 80)
    #expect(grams.mode == .grams)
    #expect(NutritionTargetSplit.prefill(from: grams) == NutritionTargetSplit(kcal: 2400, proteinPct: 25, carbsPct: 45, fatPct: 30))
    #expect(NutritionTargetSplit.prefill(from: .none) == NutritionTargetSplit(kcal: nil, proteinPct: nil, carbsPct: nil, fatPct: nil))
}

@Test func theCustomFoodFormReadsTheLabel() {
    let draft = FoodCustomForm.draft(
        name: " Granola ", brand: "", kcal: "450", protein: "12,5", carbs: "", fat: "18",
        fiber: "", sugar: "20", salt: "", saturatedFat: "5", serving: "40"
    )
    #expect(draft == FoodCustomDraft(
        name: "Granola", brand: nil, kcalPer100g: 450, proteinPer100g: 12.5, carbsPer100g: 0, fatPer100g: 18,
        fiberPer100g: nil, sugarPer100g: 20, saltPer100g: nil, saturatedFatPer100g: 5, servingGrams: 40
    ))
    #expect(FoodCustomForm.draft(name: "", brand: "", kcal: "450", protein: "", carbs: "", fat: "", fiber: "", sugar: "", salt: "", saturatedFat: "", serving: "") == nil)
    #expect(FoodCustomForm.draft(name: "x", brand: "", kcal: "1200", protein: "", carbs: "", fat: "", fiber: "", sugar: "", salt: "", saturatedFat: "", serving: "") == nil)
}

@Test func theMealSuggestedFollowsTheHour() throws {
    let calendar = Calendar(identifier: .gregorian)
    func at(_ hour: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour)))
    }
    #expect(FoodLogMeal.suggested(at: try at(8), calendar: calendar) == .breakfast)
    #expect(FoodLogMeal.suggested(at: try at(13), calendar: calendar) == .lunch)
    #expect(FoodLogMeal.suggested(at: try at(16), calendar: calendar) == .snacks)
    #expect(FoodLogMeal.suggested(at: try at(20), calendar: calendar) == .dinner)
}

@Test func theDaysOwnLogWinsOverImportedMeals() {
    #expect(NutritionMealsMode.resolve(foodLogReady: true, foodLogEntries: 2, importedMeals: 3) == .foodLog)
    #expect(NutritionMealsMode.resolve(foodLogReady: true, foodLogEntries: 0, importedMeals: 0) == .foodLog)
    // A day imported from MyFitnessPal keeps its meals, read-only.
    #expect(NutritionMealsMode.resolve(foodLogReady: true, foodLogEntries: 0, importedMeals: 3) == .imported)
    #expect(NutritionMealsMode.resolve(foodLogReady: false, foodLogEntries: 0, importedMeals: 0) == .none)
}

// MARK: - Store

private actor StubFoodLog: FoodLogServing {
    var day = V1FoodLogDay(trainingDayId: "2026-10-01", entries: [])
    var failure: (any Error)?
    private(set) var added: [FoodLogDraft] = []
    private(set) var deleted: [String] = []
    private(set) var targetsSent: [V1NutritionTargets] = []
    var ownFoods: [V1FoodProduct] = []
    private(set) var deletedFoods: [String] = []
    var barcodeProducts: [String: V1FoodProduct] = [:]
    private(set) var barcodesRead: [String] = []

    func stock(_ product: V1FoodProduct, barcode: String) { barcodeProducts[barcode] = product }

    init(day: V1FoodLogDay? = nil, failure: (any Error)? = nil, ownFoods: [V1FoodProduct] = []) {
        if let day { self.day = day }
        self.failure = failure
        self.ownFoods = ownFoods
    }

    func ownFoods(token: String) async throws -> [V1FoodProduct] {
        if let failure { throw failure }
        return ownFoods
    }

    func updateCustomFood(id: String, _ draft: FoodCustomDraft, token: String) async throws -> V1FoodProduct {
        if let failure { throw failure }
        var product = try #require(ownFoods.first { $0.id == id })
        product.name = draft.name
        product.kcalPer100g = draft.kcalPer100g
        return product
    }

    func deleteCustomFood(id: String, token: String) async throws {
        if let failure { throw failure }
        deletedFoods.append(id)
    }

    func day(trainingDayId: String, token: String) async throws -> V1FoodLogDay { day }

    func add(_ draft: FoodLogDraft, token: String) async throws -> V1FoodLogEntry {
        if let failure { throw failure }
        added.append(draft)
        return V1FoodLogEntry(
            id: "server-\(added.count)", meal: draft.meal, productId: nil, name: "Stored", brand: nil,
            grams: draft.grams, kcal: 42, protein: 1, carbs: 2, fat: 3
        )
    }

    func update(entryId: String, _ change: FoodLogEntryChange, token: String) async throws -> V1FoodLogEntry {
        if let failure { throw failure }
        let entry = try #require(day.entries.first { $0.id == entryId })
        return FoodLogStore.applying(change, to: entry)
    }

    func delete(entryId: String, token: String) async throws {
        if let failure { throw failure }
        deleted.append(entryId)
    }

    func search(_ query: String, token: String) async throws -> V1FoodSearchResults {
        V1FoodSearchResults(own: [], products: [], offUnavailable: false)
    }

    func product(barcode: String, token: String) async throws -> V1FoodProduct? {
        barcodesRead.append(barcode)
        return barcodeProducts[barcode]
    }

    func createCustomFood(_ draft: FoodCustomDraft, token: String) async throws -> V1FoodProduct { rice }

    func setTargets(_ targets: V1NutritionTargets, trainingDayId: String, token: String) async throws -> V1NutritionTargets {
        if let failure { throw failure }
        targetsSent.append(targets)
        return targets
    }

    // Saved meals and recipes (SHARPIT ADR-071)
    var copySource: [V1FoodLogEntry] = []
    private(set) var copies: [(from: String, meal: FoodLogMeal?, to: String)] = []
    var saved: [V1SavedMeal] = []
    private(set) var savedLogs: [(id: String, meal: FoodLogMeal)] = []
    private(set) var recipesSent: [(id: String?, draft: FoodRecipeDraft)] = []

    func setCopySource(_ entries: [V1FoodLogEntry]) { copySource = entries }
    func setFailure(_ error: (any Error)?) { failure = error }
    func setSaved(_ meals: [V1SavedMeal]) { saved = meals }

    func copy(from fromDayId: String, meal: FoodLogMeal?, to toDayId: String, token: String) async throws -> [V1FoodLogEntry] {
        if let failure { throw failure }
        copies.append((fromDayId, meal, toDayId))
        return copySource.filter { meal == nil || $0.meal == meal }
    }

    func savedMeals(token: String) async throws -> [V1SavedMeal] {
        if let failure { throw failure }
        return saved
    }

    func saveMeal(name: String, trainingDayId: String, meal: FoodLogMeal, token: String) async throws -> V1SavedMeal {
        if let failure { throw failure }
        let kept = V1SavedMeal(id: "m\(saved.count + 1)", name: name, items: [], kcal: 0, protein: 0, carbs: 0, fat: 0)
        saved.append(kept)
        return kept
    }

    func deleteSavedMeal(id: String, token: String) async throws {
        if let failure { throw failure }
        saved.removeAll { $0.id == id }
    }

    func logSavedMeal(id: String, trainingDayId: String, meal: FoodLogMeal, token: String) async throws -> [V1FoodLogEntry] {
        if let failure { throw failure }
        savedLogs.append((id, meal))
        let items = saved.first { $0.id == id }?.items ?? []
        return items.enumerated().map { index, item in
            V1FoodLogEntry(
                id: "logged-\(index)", meal: meal, productId: item.productId, name: item.name, brand: item.brand,
                grams: item.grams, kcal: item.kcal, protein: item.protein, carbs: item.carbs, fat: item.fat
            )
        }
    }

    func saveRecipe(id: String?, _ draft: FoodRecipeDraft, token: String) async throws -> V1FoodProduct {
        if let failure { throw failure }
        recipesSent.append((id, draft))
        var product = rice
        product.name = draft.name
        return product
    }
}

@MainActor
private final class Recorder {
    var reloads = 0
    var failures: [String] = []
}

@MainActor
private func makeStore(_ client: StubFoodLog, recorder: Recorder) -> FoodLogStore {
    FoodLogStore(
        trainingDayId: "2026-10-01",
        client: client,
        tokenProvider: { "t" },
        onChange: { recorder.reloads += 1 },
        reportFailure: { recorder.failures.append($0) }
    )
}

@MainActor
@Test func theDayIsGroupedByMealInTheOrderItIsRead() async throws {
    let day = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))
    let store = makeStore(StubFoodLog(day: day), recorder: Recorder())
    await store.load(trainingDayId: "2026-10-01")

    #expect(store.phase == .ready)
    #expect(store.sections.map(\.meal) == [.breakfast, .lunch, .dinner, .snacks])
    #expect(store.sections.map(\.meal.label) == ["Petit-déjeuner", "Déjeuner", "Dîner", "Collations"])
    #expect(store.section(.lunch).entries.map(\.id) == ["e2"])
    #expect(store.section(.dinner).entries.isEmpty)
    #expect(store.section(.lunch).kcal == 525)
    #expect(store.lastGrams(of: rice) == 150)
    #expect(store.targets.kcal == 2400)
}

@MainActor
@Test func anAddShowsAtOnceThenTakesTheServersEntry() async {
    let client = StubFoodLog()
    let recorder = Recorder()
    let store = makeStore(client, recorder: recorder)
    await store.load(trainingDayId: "2026-10-01")

    let draft = FoodLogDraft(trainingDayId: "2026-10-01", meal: .lunch, grams: 155, source: .product(rice))
    let pending = FoodLogStore.pendingEntry(for: draft)
    #expect(pending.isPending)
    #expect(pending.kcal == 542.5)

    await store.add(draft)
    #expect(store.entries.map(\.id) == ["server-1"])
    #expect(store.recent.first?.product.id == "p1")
    #expect(recorder.reloads == 1)
    #expect(recorder.failures.isEmpty)
    #expect(await client.added == [draft])
}

@MainActor
@Test func anAddThatFailsIsTakenBackAndSaid() async {
    let recorder = Recorder()
    let store = makeStore(StubFoodLog(failure: SharpitAPIError.badRequest), recorder: recorder)
    await store.load(trainingDayId: "2026-10-01")

    await store.add(FoodLogDraft(
        trainingDayId: "2026-10-01", meal: .snacks, grams: 30,
        source: .quick(FoodQuickAdd(name: "Barre", kcal: 120))
    ))
    #expect(store.entries.isEmpty)
    #expect(recorder.reloads == 0)
    #expect(recorder.failures == ["Aliment non ajouté. Réessaie dans un instant."])
}

@MainActor
@Test func aDeleteThatFailsPutsTheEntryBackInPlace() async throws {
    let day = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))
    let recorder = Recorder()
    let store = makeStore(StubFoodLog(day: day, failure: SharpitAPIError.unauthorized), recorder: recorder)
    await store.load(trainingDayId: "2026-10-01")

    await store.delete(try #require(store.entries.first { $0.id == "e1" }))
    #expect(store.entries.map(\.id) == ["e2", "e1", "e3"])
    #expect(recorder.failures == ["Aliment non supprimé : ta session a expiré."])
}

@MainActor
@Test func aDeleteRemovesTheEntryAndReloadsTheDay() async throws {
    let day = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))
    let client = StubFoodLog(day: day)
    let recorder = Recorder()
    let store = makeStore(client, recorder: recorder)
    await store.load(trainingDayId: "2026-10-01")

    await store.delete(try #require(store.entries.first { $0.id == "e2" }))
    #expect(store.entries.map(\.id) == ["e1", "e3"])
    #expect(await client.deleted == ["e2"])
    #expect(recorder.reloads == 1)
}

@MainActor
@Test func anEditMovesTheEntryAndRescalesIt() async throws {
    let day = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))
    let store = makeStore(StubFoodLog(day: day), recorder: Recorder())
    await store.load(trainingDayId: "2026-10-01")

    let rice = try #require(store.entries.first { $0.id == "e2" })
    await store.update(rice, FoodLogEntryChange(grams: 75, meal: .dinner))
    let moved = try #require(store.section(.dinner).entries.first)
    #expect(moved.grams == 75)
    #expect(moved.kcal == 262.5)
    #expect(store.section(.lunch).entries.isEmpty)
}

@MainActor
@Test func targetsThatFailToSaveAreRestored() async throws {
    let day = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))
    let recorder = Recorder()
    let store = makeStore(StubFoodLog(day: day, failure: SharpitAPIError.transport), recorder: recorder)
    await store.load(trainingDayId: "2026-10-01")

    await store.setTargets(V1NutritionTargets(kcal: 3000, proteinG: nil, carbsG: nil, fatG: nil))
    #expect(store.targets.kcal == 2400)
    #expect(recorder.failures == ["Objectifs non enregistrés : pas de connexion internet."])
}

@MainActor
@Test func anotherDayNeverShowsUnderTheDateOfThePrevious() async throws {
    let day = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))
    let store = makeStore(StubFoodLog(day: day), recorder: Recorder())
    await store.load(trainingDayId: "2026-10-01")
    #expect(store.hasEntries)

    await store.load(trainingDayId: "2026-09-30")
    #expect(store.trainingDayId == "2026-09-30")
}

// MARK: - Search

@MainActor
@Test func aShortQueryIsNotSearched() async {
    let search = FoodSearchStore(client: StubFoodLog(), tokenProvider: { "t" }, debounce: .zero)
    search.setQuery("r")
    await search.settle()
    #expect(search.results == nil)
    #expect(!search.isSearching)

    search.setQuery("riz")
    await search.settle()
    #expect(search.results == V1FoodSearchResults(own: [], products: [], offUnavailable: false))
    #expect(!search.isSearching)
}

@MainActor
@Test func anUnknownBarcodeOffersToTypeItIn() async {
    let search = FoodSearchStore(client: StubFoodLog(), tokenProvider: { "t" }, debounce: .zero)
    #expect(await search.lookUp(barcode: "3017620422003") == .unknown)
}

@MainActor
@Test func aSearchHitIsCompletedByItsBarcodeRead() async throws {
    let client = StubFoodLog()
    let summary = try JSONDecoder().decode(V1FoodHealth.self, from: Data(scoredV2JSON.utf8))
    var hit = V1FoodProduct(
        id: "p1", source: "OFF", barcode: "3017620422003", name: "Gel", brand: nil,
        kcalPer100g: 300, proteinPer100g: 0, carbsPer100g: 75, fatPer100g: 0,
        fiberPer100g: nil, sugarPer100g: 40, servingGrams: nil, servingLabel: nil, health: summary
    )
    var full = hit
    full.health?.detail = .full
    full.health?.additivesKnown = .list
    await client.stock(full, barcode: "3017620422003")
    let search = FoodSearchStore(client: client, tokenProvider: { "t" }, debounce: .zero)

    #expect(await search.fullProduct(of: hit)?.health?.detail == .full)

    hit.source = "CUSTOM"
    #expect(await search.fullProduct(of: hit) == nil)
    #expect(await client.barcodesRead == ["3017620422003"])
}

// MARK: - Own foods

private nonisolated func ownFood(_ id: String, _ name: String) -> V1FoodProduct {
    V1FoodProduct(
        id: id, source: "CUSTOM", barcode: nil, name: name, brand: nil,
        kcalPer100g: 400, proteinPer100g: 10, carbsPer100g: 50, fatPer100g: 15,
        fiberPer100g: nil, sugarPer100g: nil, servingGrams: nil, servingLabel: nil
    )
}

@MainActor
@Test func ownFoodsLoadSortedAndAnEditReplacesTheFood() async throws {
    let client = StubFoodLog(ownFoods: [ownFood("c2", "Muesli"), ownFood("c1", "Granola")])
    let store = OwnFoodsStore(client: client, tokenProvider: { "t" })
    await store.load()
    #expect(store.phase == .ready)
    #expect(store.foods.map(\.name) == ["Granola", "Muesli"])

    var draft = FoodCustomDraft(product: store.foods[1])
    draft.name = "Avoine"
    draft.kcalPer100g = 380
    let stored = try await store.update(store.foods[1], with: draft)
    #expect(stored.kcalPer100g == 380)
    #expect(store.foods.map(\.name) == ["Avoine", "Granola"])
}

@MainActor
@Test func aDeletedOwnFoodLeavesTheListAndComesBackIfRefused() async {
    let client = StubFoodLog(ownFoods: [ownFood("c1", "Granola"), ownFood("c2", "Muesli")])
    let store = OwnFoodsStore(client: client, tokenProvider: { "t" })
    await store.load()

    #expect(await store.delete(store.foods[0]))
    #expect(store.foods.map(\.id) == ["c2"])
    #expect(await client.deletedFoods == ["c1"])

    let refusing = StubFoodLog(failure: SharpitAPIError.badRequest, ownFoods: [ownFood("c1", "Granola")])
    let refused = OwnFoodsStore(client: refusing, tokenProvider: { "t" })
    await refused.load()
    #expect(refused.phase == .failed(SharpitErrorGuidance.message(for: SharpitAPIError.badRequest, subject: "La liste de tes aliments")))
}

@MainActor
@Test func aCreatedFoodJoinsMyFoodsAndTheRecentFollowEdits() async throws {
    let store = OwnFoodsStore(client: StubFoodLog(), tokenProvider: { "t" })
    await store.load()
    store.add(ownFood("c9", "Barre maison"))
    store.add(rice)
    #expect(store.foods.map(\.id) == ["c9"])

    let day = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))
    let log = makeStore(StubFoodLog(day: day), recorder: Recorder())
    await log.load(trainingDayId: "2026-10-01")
    var renamed = try #require(log.recent.first?.product)
    renamed.name = "Riz complet"
    log.productChanged(renamed)
    #expect(log.recent.first?.product.name == "Riz complet")
    #expect(log.recent.first?.lastGrams == 150)
    log.productDeleted(renamed)
    #expect(log.recent.isEmpty)
}

@Test func aNewPortionKeepsTheScoreTheRowShowed() throws {
    let health = try JSONDecoder().decode(V1FoodHealth.self, from: Data(scoredV2JSON.utf8))
    var shown = V1FoodLogEntry(
        id: "e", meal: .lunch, productId: "p1", name: "Riz", brand: nil, grams: 150,
        kcal: 525, protein: 11, carbs: 115, fat: 1.5
    )
    shown.health = health
    var echo = shown
    echo.grams = 200
    echo.health = nil
    // An echo without a score (a server before the fix) keeps the one shown.
    #expect(FoodLogStore.keepingHealth(of: shown, in: echo).health == health)
    #expect(FoodLogStore.keepingHealth(of: shown, in: echo).grams == 200)
    // Another food, or a score in the echo, is the server's word.
    echo.productId = "p2"
    #expect(FoodLogStore.keepingHealth(of: shown, in: echo).health == nil)
}

// MARK: - Meal and day score (SHARPIT ADR-070)

private let dayHealthJSON = """
{ "day": { "score": 71, "grade": "good", "coverage": 0.86, "kcal": 692, "protein": 15.6, "fiber": null,
           "ultraProcessedShare": null,
           "highlights": [{ "key": "partial_coverage", "tone": "neutral", "label": "Note partielle",
                            "detail": "86 % de l'énergie vient d'aliments notés" }] },
  "meals": { "BREAKFAST": null,
             "LUNCH": { "score": 74, "grade": "good", "coverage": 1, "kcal": 525, "protein": 11.3, "fiber": null,
                        "ultraProcessedShare": 0,
                        "highlights": [{ "key": "protein_meal_low", "tone": "negative", "label": "Peu de protéines",
                                         "detail": "11 g dans le repas" }] },
             "DINNER": null, "SNACKS": null } }
"""

@Test func theDayDecodesTheScoreOfEachMealAndOfTheDay() throws {
    let health = try JSONDecoder().decode(V1FoodLogDayHealth.self, from: Data(dayHealthJSON.utf8))
    #expect(health.day?.score == 71)
    #expect(health.meal(.lunch)?.grade == .good)
    #expect(health.meal(.lunch)?.highlights.first?.key == "protein_meal_low")
    #expect(health.meal(.dinner) == nil)

    let older = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))
    #expect(older.health == nil)
}

@MainActor
@Test func aMealChangedSinceItWasScoredShowsNoScore() async throws {
    let read = try JSONDecoder().decode(V1FoodLogDay.self, from: Data(dayJSON.utf8))
    let health = try JSONDecoder().decode(V1FoodLogDayHealth.self, from: Data(dayHealthJSON.utf8))
    let day = V1FoodLogDay(
        trainingDayId: read.trainingDayId, entries: read.entries, health: health,
        targets: read.targets, recent: read.recent
    )
    let store = makeStore(StubFoodLog(day: day), recorder: Recorder())
    await store.load(trainingDayId: "2026-10-01")
    #expect(store.mealHealth(.lunch)?.score == 74)
    #expect(store.dayHealth?.score == 71)

    // The stub keeps answering the day as first read: the lunch it scored is not the one shown.
    await store.delete(try #require(store.entries.first { $0.id == "e2" }))
    #expect(store.mealHealth(.lunch) == nil)
    #expect(store.dayHealth == nil)
    #expect(store.mealHealth(.dinner) == nil)
}


// MARK: - Copy, saved meals and recipes (SHARPIT ADR-071)

private nonisolated let skyrItem = V1SavedMealItem(
    productId: "skyr", name: "Skyr", brand: nil, grams: 150, kcal: 93, protein: 16, carbs: 6, fat: 0.3,
    fiber: nil, sugar: nil
)

@Test func theDayBeforeIsReadOnTheCalendar() {
    #expect(TrainingDayId.previous("2026-10-05") == "2026-10-04")
    #expect(TrainingDayId.previous("2026-03-01") == "2026-02-28")
    #expect(TrainingDayId.previous("2026-01-01") == "2025-12-31")
    #expect(TrainingDayId.previous("hier") == nil)
}

@Test func aSavedMealIsNamedByItsFoodsHeaviestFirst() {
    func entry(_ name: String, _ kcal: Double) -> V1FoodLogEntry {
        V1FoodLogEntry(id: name, meal: .lunch, productId: nil, name: name, brand: nil, grams: 100, kcal: kcal, protein: 0, carbs: 0, fat: 0)
    }
    #expect(SavedMealNaming.defaultName([entry("Banane", 90), entry("Skyr", 120)]) == "Skyr, Banane")
    #expect(SavedMealNaming.defaultName([entry("A", 4), entry("B", 3), entry("C", 2), entry("D", 1)]) == "A, B, C…")
}

@MainActor
@Test func aMealCopiedFromTheDayBeforeJoinsTheDay() async {
    let client = StubFoodLog()
    let lunch = V1FoodLogEntry(id: "c1", meal: .lunch, productId: nil, name: "Riz", brand: nil, grams: 150, kcal: 200, protein: 4, carbs: 40, fat: 1)
    await client.setCopySource([lunch])
    let recorder = Recorder()
    let store = makeStore(client, recorder: recorder)
    await store.load(trainingDayId: "2026-10-01")

    await store.copyFromPreviousDay(.lunch)

    #expect(store.section(.lunch).entries.map(\.id) == ["c1"])
    let copies = await client.copies
    #expect(copies.first?.from == "2026-09-30")
    #expect(copies.first?.meal == .lunch)
    #expect(copies.first?.to == "2026-10-01")
    #expect(recorder.reloads == 1)
}

@MainActor
@Test func copyingAnEmptyMealSaysThereWasNothing() async {
    let recorder = Recorder()
    let store = makeStore(StubFoodLog(), recorder: recorder)
    await store.load(trainingDayId: "2026-10-01")

    await store.copyFromPreviousDay(.dinner)

    #expect(store.entries.isEmpty)
    #expect(recorder.failures == ["Ce repas était vide la veille : rien à copier."])
    #expect(recorder.reloads == 0)
}

@MainActor
@Test func aSavedMealLogsWholeIntoTheMealAsked() async {
    let client = StubFoodLog()
    let saved = V1SavedMeal(id: "m1", name: "Goûter", items: [skyrItem], kcal: 93, protein: 16, carbs: 6, fat: 0.3)
    await client.setSaved([saved])
    let store = makeStore(client, recorder: Recorder())
    await store.load(trainingDayId: "2026-10-01")

    await store.logSavedMeal(saved, into: .snacks)

    #expect(store.section(.snacks).entries.map(\.id) == ["logged-0"])
    #expect(store.section(.snacks).kcal == 93)
    #expect(await client.savedLogs.first?.meal == .snacks)
}

@MainActor
@Test func aSavedMealThatFailsLeavesTheDayAsItWas() async {
    let client = StubFoodLog(failure: SharpitAPIError.unauthorized)
    let recorder = Recorder()
    let store = makeStore(client, recorder: recorder)
    let saved = V1SavedMeal(id: "m1", name: "Goûter", items: [skyrItem], kcal: 93, protein: 16, carbs: 6, fat: 0.3)

    await store.logSavedMeal(saved, into: .snacks)

    #expect(store.entries.isEmpty)
    #expect(recorder.failures == ["Repas non ajouté : ta session a expiré."])
}

@MainActor
@Test func aSavedMealIsDeletedAtOnceAndPutBackIfRefused() async {
    let client = StubFoodLog()
    let saved = V1SavedMeal(id: "m1", name: "Goûter", items: [skyrItem], kcal: 93, protein: 16, carbs: 6, fat: 0.3)
    await client.setSaved([saved])
    let store = SavedMealsStore(client: client, tokenProvider: { "t" })
    await store.load()
    #expect(store.meals.map(\.id) == ["m1"])

    await client.setFailure(SharpitAPIError.badRequest)
    await store.delete(saved)

    #expect(store.meals.map(\.id) == ["m1"])
    #expect(store.failure == "Repas non supprimé. Réessaie dans un instant.")
}

@Test func aRecipeLabelSumsItsIngredientsOverTheCookedWeight() throws {
    var builder = FoodRecipeBuilder()
    builder.name = "Riz au poulet"
    builder.add(rice)
    builder.add(rice)
    #expect(builder.lines.count == 1)

    let label = try #require(builder.label)
    #expect(label.kcalPer100g == rice.kcalPer100g)

    builder.lines[0].gramsText = "100"
    builder.cookedGramsText = "250"
    builder.servingsText = "2"
    let cooked = try #require(builder.label)
    #expect(cooked.kcalPer100g == (rice.kcalPer100g * 100 / 250 * 10).rounded() / 10)
    #expect(cooked.servingGrams == 125)

    let draft = try #require(builder.draft)
    #expect(draft.ingredients == [.init(productId: rice.id, grams: 100)])
    #expect(draft.cookedGrams == 250)
    #expect(draft.servings == 2)
}

@Test func aRecipeSaysWhatItLacks() {
    var builder = FoodRecipeBuilder()
    #expect(builder.problem == "Donne un nom à ta recette.")
    builder.name = "Bol"
    #expect(builder.problem == "Ajoute au moins un ingrédient.")
    builder.add(rice)
    builder.lines[0].gramsText = ""
    #expect(builder.problem == "Indique les grammes de « \(rice.name) ».")
    builder.lines[0].gramsText = "80"
    builder.servingsText = "0"
    #expect(builder.problem == "Le nombre de parts va de 1 à 50.")
    #expect(builder.draft == nil)
}

@Test func aSavedRecipeReopensAsItWasBuilt() {
    var product = rice
    product.recipe = V1Recipe(
        ingredients: [V1RecipeIngredient(product: rice, grams: 120)], cookedGrams: 300, servings: nil, totalGrams: 300
    )
    let builder = FoodRecipeBuilder(recipe: product)
    #expect(builder.lines.map(\.gramsText) == ["120"])
    #expect(builder.cookedGramsText == "300")
    #expect(builder.servingsText.isEmpty)
}

@Test func aRecipeBodyCarriesItsIngredientsAndNullsWhatIsNotGiven() throws {
    let draft = FoodRecipeDraft(name: "Bol", ingredients: [.init(productId: "rice", grams: 80)], cookedGrams: nil, servings: 2)
    let body = try FoodLogClient.body(for: draft)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["name"] as? String == "Bol")
    #expect(object["cookedGrams"] is NSNull)
    #expect(object["servings"] as? Int == 2)
    let ingredients = try #require(object["ingredients"] as? [[String: Any]])
    #expect(ingredients.first?["productId"] as? String == "rice")
}

@Test func aSavedMealAndARecipeDecodeAsTheServerSendsThem() throws {
    let json = """
    {"meals":[{"id":"m1","name":"Goûter","items":[{"productId":"skyr","name":"Skyr","brand":null,"grams":150,"kcal":93,"protein":16,"carbs":6,"fat":0.3,"fiber":null,"sugar":null}],"kcal":93,"protein":16,"carbs":6,"fat":0.3,"health":null,"updatedAt":"2026-10-05T08:00:00.000Z"}]}
    """
    let meals = try JSONDecoder().decode(V1SavedMealList.self, from: Data(json.utf8)).meals
    #expect(meals.first?.items.first?.grams == 150)

    let product = """
    {"id":"r1","source":"CUSTOM","barcode":null,"name":"Bol","brand":null,"kcalPer100g":120,"proteinPer100g":8,"carbsPer100g":15,"fatPer100g":3,"fiberPer100g":null,"sugarPer100g":null,"servingGrams":200,"servingLabel":"1 part · 200 g","recipe":{"ingredients":[{"productId":"rice","name":"Riz","brand":null,"grams":80,"kcalPer100g":350,"proteinPer100g":7,"carbsPer100g":78,"fatPer100g":1,"fiberPer100g":null,"sugarPer100g":null,"saltPer100g":null,"saturatedFatPer100g":null}],"cookedGrams":null,"servings":2,"totalGrams":400}}
    """
    let decoded = try JSONDecoder().decode(V1FoodProduct.self, from: Data(product.utf8))
    #expect(decoded.isRecipe)
    #expect(decoded.recipe?.ingredients.first?.kcalPer100g == 350)
}
