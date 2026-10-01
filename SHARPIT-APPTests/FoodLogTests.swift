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
}

@Test func anUnknownMealKeyReadsAsASnack() throws {
    let entry = try JSONDecoder().decode(V1FoodLogEntry.self, from: Data("""
    { "id": "e", "meal": "BRUNCH", "name": "x", "grams": 1, "kcal": 1, "protein": 0, "carbs": 0, "fat": 0 }
    """.utf8))
    #expect(entry.meal == .snacks)
}

@Test func theNutritionDayTellsMyFitnessPalApartFromTheLog() throws {
    let json = { (extra: String) in
        """
        { "apiVersion": 1, "trainingDayId": "2026-10-01", "connected": true, \(extra) "empty": null, "day": null,
          "coachReading": null, "diet": [], "history": [] }
        """
    }
    let current = try JSONDecoder().decode(V1NutritionResponse.self, from: Data(json("\"mfpConnected\": false,").utf8))
    #expect(current.connected)
    #expect(!current.mfpConnected)

    // A server older than ADR-061 only said `connected`, which then meant MyFitnessPal.
    let older = try JSONDecoder().decode(V1NutritionResponse.self, from: Data(json("").utf8))
    #expect(older.mfpConnected)
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
    #expect(body["kcal"] as? Int == 2200)
    #expect(body["proteinG"] is NSNull)
    #expect(body["carbsG"] as? Double == 280)
    #expect(body["fatG"] is NSNull)
}

@Test func aCustomFoodSendsItsMissingOptionsAsNull() throws {
    let body = try object(FoodLogClient.body(for: FoodCustomDraft(
        name: "Granola", brand: nil, kcalPer100g: 450, proteinPer100g: 12, carbsPer100g: 55, fatPer100g: 18,
        fiberPer100g: 8, sugarPer100g: nil, servingGrams: nil
    )))
    #expect(body["brand"] is NSNull)
    #expect(body["fiberPer100g"] as? Double == 8)
    #expect(body["sugarPer100g"] is NSNull)
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
    // A day only MyFitnessPal filled keeps its meals, read-only.
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

    init(day: V1FoodLogDay? = nil, failure: (any Error)? = nil) {
        if let day { self.day = day }
        self.failure = failure
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

    func product(barcode: String, token: String) async throws -> V1FoodProduct? { nil }

    func createCustomFood(_ draft: FoodCustomDraft, token: String) async throws -> V1FoodProduct { rice }

    func setTargets(_ targets: V1NutritionTargets, trainingDayId: String, token: String) async throws -> V1NutritionTargets {
        if let failure { throw failure }
        targetsSent.append(targets)
        return targets
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
