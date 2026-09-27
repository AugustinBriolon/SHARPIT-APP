import Foundation
import Testing
@testable import Sharpit

// MARK: - /api/v1/nutrition

private let nutritionJSON = """
{
  "apiVersion": 1,
  "trainingDayId": "2026-09-27",
  "connected": true,
  "empty": null,
  "day": {
    "calories": 2140.5, "protein": 128, "carbohydrates": 260, "fat": 71.2,
    "fiber": 31, "sugar": null, "complete": false,
    "goals": {
      "calories": { "consumed": 2140.5, "goal": 2400, "remaining": 259.5, "pct": 89 },
      "protein": { "consumed": 128, "goal": 140, "remaining": 12, "pct": 91 },
      "carbohydrates": { "consumed": 260, "goal": 300, "remaining": 40, "pct": 87 },
      "fat": { "consumed": 71.2, "goal": 80, "remaining": 8.8, "pct": 89 },
      "exerciseCalories": 450, "calorieBudget": 2850
    },
    "fuelDensity": { "proteinGPerKg": 1.8, "carbohydratesGPerKg": 3.7, "referenceWeightKg": 70.5 },
    "meals": [
      { "name": "breakfast", "label": "Petit-déjeuner", "calories": 520, "protein": 25, "carbs": 70, "fat": 14,
        "entries": [{ "name": "Flocons d’avoine", "calories": 300, "protein": 10, "carbs": 54, "fat": 6 }] }
    ]
  },
  "coachReading": {
    "state": "ready", "status": "PROVISIONAL", "refreshing": false, "generatedAt": "2026-09-27T12:00:00.000Z",
    "verdict": { "headline": "Carburant juste pour la séance de ce soir", "tone": "watch" },
    "findings": [{ "job": "fuel", "text": "Glucides sous l’objectif avant l’intensité." }],
    "action": { "text": "Ajoute une collation glucidique vers 17 h." },
    "flaggedEntries": [{ "meal": "breakfast", "entry": "Flocons d’avoine", "reason": "ultra_processed" }]
  },
  "diet": ["Végétarien"],
  "history": [
    { "date": "2026-09-26", "calories": null, "goalCalories": null },
    { "date": "2026-09-27", "calories": 2140.5, "goalCalories": 2400 }
  ]
}
"""

@Test func theNutritionDayDecodesWithItsReading() throws {
    let nutrition = try JSONDecoder().decode(V1NutritionResponse.self, from: Data(nutritionJSON.utf8))

    let day = try #require(nutrition.day)
    #expect(day.goals?.calories.remaining == 259.5)
    #expect(day.meals.first?.entries.first?.name == "Flocons d’avoine")
    #expect(nutrition.diet == ["Végétarien"])
    guard case .ready(let ready) = nutrition.coachReading else {
        Issue.record("expected a ready reading")
        return
    }
    #expect(ready.isProvisional)
    #expect(ready.verdict.tone == .watch)
    #expect(nutrition.dataByDay == ["2026-09-26": false, "2026-09-27": true])
}

@Test func anUnknownReadingShapeDoesNotCostTheDay() throws {
    let json = nutritionJSON.replacingOccurrences(of: "\"verdict\": {", with: "\"verdictV2\": {")
    let nutrition = try JSONDecoder().decode(V1NutritionResponse.self, from: Data(json.utf8))

    #expect(nutrition.day != nil)
    #expect(nutrition.coachReading == nil)
}

@Test func belowProTheReadingIsAnnouncedNotSent() throws {
    let json = """
    { "apiVersion": 1, "trainingDayId": "2026-09-27", "connected": true, "empty": null,
      "day": { "calories": 1200, "protein": 60, "carbohydrates": 150, "fat": 40, "fiber": null, "sugar": null,
               "complete": false, "goals": null, "fuelDensity": null, "meals": [] },
      "coachReading": { "state": "pro_required" }, "diet": [], "history": [] }
    """
    let nutrition = try JSONDecoder().decode(V1NutritionResponse.self, from: Data(json.utf8))
    #expect(nutrition.coachReading == V1NutritionCoachReading.proRequired)
    #expect(nutrition.day?.calories == 1200)
}

@Test func aPendingReadingDecodesByItsState() throws {
    let json = """
    { "apiVersion": 1, "trainingDayId": "2026-09-27", "connected": true, "empty": null, "day": null,
      "coachReading": { "state": "awaiting_day_end" }, "diet": [], "history": [] }
    """
    let nutrition = try JSONDecoder().decode(V1NutritionResponse.self, from: Data(json.utf8))
    #expect(nutrition.coachReading == .awaitingDayEnd)
}

// MARK: - Readout

@Test func caloriesReadTheFrenchWay() {
    #expect(NutritionReadout.kcal(2140.5) == "2\u{202F}141")
    #expect(NutritionReadout.kcal(nil) == "—")
    #expect(NutritionReadout.grams(71.2) == "71 g")
    #expect(NutritionReadout.perKg(1.84) == "1,8 g/kg")
}

@Test func theRemainingCaloriesSayWhichSideOfTheGoal() {
    #expect(NutritionReadout.remainingLabel(259.5) == "Reste 260 kcal")
    #expect(NutritionReadout.remainingLabel(-120) == "120 kcal au-delà")
    #expect(NutritionReadout.remainingLabel(nil) == nil)
}

@Test func aGoalBarFillsUpToTheGoalOnly() {
    #expect(NutritionReadout.fill(pct: 45) == 0.45)
    #expect(NutritionReadout.fill(pct: 130) == 1)
    #expect(NutritionReadout.fill(pct: nil) == 0)
}

@Test func onTrackMeansWithinTenPercent() {
    #expect(NutritionReadout.isOnGoal(pct: 92))
    #expect(NutritionReadout.isOnGoal(pct: 110))
    #expect(!NutritionReadout.isOnGoal(pct: 80))
    #expect(!NutritionReadout.isOnGoal(pct: 125))
}

@Test func findingsUseTheWebsLabels() {
    #expect(NutritionReadout.jobLabel("quality") == "Produits")
    #expect(NutritionReadout.jobLabel("weight") == "Objectif de poids")
    #expect(NutritionReadout.flagLabel("diet_conflict") == "Hors régime")
}

// MARK: - Résumé card

private struct StubNutrition: NutritionServing {
    let result: Result<V1NutritionResponse, SharpitAPIError>

    func nutrition(trainingDayId: String, token: String) async throws -> V1NutritionResponse {
        try result.get()
    }
}

@MainActor
@Test func theCardReflectsTheLogState() async throws {
    let decoded = try JSONDecoder().decode(V1NutritionResponse.self, from: Data(nutritionJSON.utf8))
    let loaded = NutritionTodayStore(client: StubNutrition(result: .success(decoded)), tokenProvider: { "t" })
    await loaded.load(trainingDayId: "2026-09-27")
    #expect(loaded.phase == .loaded(try #require(decoded.day)))

    #expect(NutritionTodayStore.phase(for: V1NutritionResponse(trainingDayId: "2026-09-27", connected: false, day: nil)) == .disconnected)
    #expect(NutritionTodayStore.phase(for: V1NutritionResponse(trainingDayId: "2026-09-27", day: nil)) == .empty)
}

@MainActor
@Test func aFailedFirstReadSaysSo() async {
    let store = NutritionTodayStore(client: StubNutrition(result: .failure(.transport)), tokenProvider: { "t" })
    await store.load(trainingDayId: "2026-09-27")
    #expect(store.phase == .failed)
}
