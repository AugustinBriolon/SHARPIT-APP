#if DEBUG
import Foundation

/// One athlete's worth of sample answers, for looking at a screen in the simulator without an
/// account or a server (`-SharpitScreenDemo …`). Debug builds only. The payloads are the ones the
/// unit tests decode, extended where a page needs more rows; every write is accepted and dropped.
nonisolated enum DemoDataset {
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static let journalAnalyses = #"""
{"apiVersion": 1, "minDays": 7, "daysWithSignal": 29, "daysInSpan": 31, "reading": {"headline": "2 associations nettes · pistes à confirmer", "verdict": "Ton levier le plus net : « Alcool », 52 minutes de sommeil en moins.", "summary": "29 jours analysés · 2 associations nettes · 1 à confirmer", "actionHint": "Teste 7 jours sans « Alcool » (ou en réduisant), puis compare sommeil et récupération.", "strengths": ["Yoga · sommeil plus haut"]}, "lifts": [{"outcome": "sleepMinutes", "title": "Sommeil", "ticks": [{"label": "5 h 30", "pct": 0}, {"label": "6 h 30", "pct": 33.3}, {"label": "7 h 30", "pct": 66.7}, {"label": "8 h 30", "pct": 100}], "rows": [{"key": "yoga:plus:sleepMinutes", "habit": "Yoga", "lagLabel": null, "weak": false, "withoutLabel": "7 h 00", "withLabel": "7 h 40", "deltaLabel": "+40′", "mediansLabel": "sans 7 h 00 → avec 7 h 40", "overlapSentence": "3 jours sur 3 avec l’habitude restent sous la médiane sans : l’écart est net, mais la règle n’est pas absolue.", "withoutPct": 50, "withPct": 72.2, "withDaysPct": [11.1, 23.3, 27.8], "withoutDaysPct": [52.2, 44.4, 61.1], "nYes": 7, "nNo": 22}]}], "drags": [{"outcome": "sleepMinutes", "title": "Sommeil", "ticks": [{"label": "5 h 30", "pct": 0}, {"label": "6 h 30", "pct": 33.3}, {"label": "7 h 30", "pct": 66.7}, {"label": "8 h 30", "pct": 100}], "rows": [{"key": "alcohol:minus:sleepMinutes", "habit": "Alcool", "lagLabel": "mesure +1 j", "weak": false, "withoutLabel": "7 h 04", "withLabel": "6 h 12", "deltaLabel": "−52′", "mediansLabel": "sans 7 h 04 → avec 6 h 12", "overlapSentence": "Les 3 jours avec l’habitude sont tous sous la médiane sans : l’écart est net et régulier.", "withoutPct": 52.2, "withPct": 23.3, "withDaysPct": [11.1, 23.3, 27.8], "withoutDaysPct": [52.2, 44.4, 61.1], "nYes": 7, "nNo": 22}]}], "leads": [{"outcome": "recoveryScore", "title": "Récupération", "ticks": [{"label": "30", "pct": 0}, {"label": "50", "pct": 33.3}, {"label": "70", "pct": 66.7}, {"label": "90", "pct": 100}], "rows": [{"key": "late_meal:minus:recoveryScore", "habit": "Repas tardif", "lagLabel": null, "weak": true, "withoutLabel": "60", "withLabel": "52", "deltaLabel": "−8", "mediansLabel": "sans 60 → avec 52", "overlapSentence": "Les 2 jours avec l’habitude sont tous sous la médiane sans : l’écart reste à confirmer et régulier.", "withoutPct": 50, "withPct": 36.7, "withDaysPct": [33.3, 36.7], "withoutDaysPct": [50, 53.3], "nYes": 7, "nNo": 22}]}]}
"""#

    static let sourcePrefs = #"""
{
  "prefs": { "version": 1, "classes": {
    "activities": { "primary": "garmin", "enabled": ["garmin", "apple-health"] },
    "wearable_health": { "primary": "garmin", "enabled": ["garmin", "apple-health"] },
    "body": { "primary": "apple-health", "enabled": ["apple-health"] },
    "nutrition": { "primary": null, "enabled": [] },
    "calendar": { "primary": null, "enabled": [] }
  } },
  "connected": ["garmin", "apple-health"],
  "classes": [
    { "id": "activities", "label": "Activités", "description": "Séances.", "providers": [
      { "id": "garmin", "name": "Garmin" }, { "id": "strava", "name": "Strava" }, { "id": "apple-health", "name": "Apple Santé" } ] },
    { "id": "wearable_health", "label": "Santé wearable", "description": "Sommeil.", "providers": [
      { "id": "garmin", "name": "Garmin" }, { "id": "apple-health", "name": "Apple Santé" } ] },
    { "id": "body", "label": "Corps", "description": "Poids.", "providers": [
      { "id": "withings", "name": "Withings" }, { "id": "apple-health", "name": "Apple Santé" } ] },
    { "id": "nutrition", "label": "Nutrition", "description": "Calories.", "providers": [
      { "id": "sharpit", "name": "Journal SharpIt" } ] }
  ]
}
"""#

    static let foodHealth = #"""
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
"""#

    static let trainingLoad = #"""
    { "apiVersion": 1, "trainingDayId": "2026-11-14",
      "days": [
        { "date": "2026-10-04", "tss": 60, "ctl": 48.0, "atl": 44.0, "tsb": 4.0 },
        { "date": "2026-10-11", "tss": 82, "ctl": 50.2, "atl": 58.0, "tsb": -7.8 },
        { "date": "2026-10-18", "tss": 55, "ctl": 53.1, "atl": 49.0, "tsb": 4.1 },
        { "date": "2026-10-25", "tss": 96, "ctl": 55.4, "atl": 66.0, "tsb": -10.6 },
        { "date": "2026-11-01", "tss": 70, "ctl": 58.0, "atl": 60.0, "tsb": -2.0 },
        { "date": "2026-11-08", "tss": 104, "ctl": 60.3, "atl": 72.0, "tsb": -11.7 },
        { "date": "2026-11-14", "tss": 80, "ctl": 62.0, "atl": 68.0, "tsb": -6.0 } ],
      "weeks": [
        { "weekEnd": "2026-09-27", "tss": 310 }, { "weekEnd": "2026-10-04", "tss": 360 },
        { "weekEnd": "2026-10-11", "tss": 402 }, { "weekEnd": "2026-10-18", "tss": 340 },
        { "weekEnd": "2026-10-25", "tss": 438 }, { "weekEnd": "2026-11-01", "tss": 470 },
        { "weekEnd": "2026-11-08", "tss": 312 }, { "weekEnd": "2026-11-15", "tss": 480 } ] }
    """#

    static let bloodTests = #"""
    { "bloodTests": [
      { "id": "t4", "sampledAt": "2026-11-12T08:00:00.000Z", "results": [
        { "markerKey": "ferritin", "value": 28, "unit": "µg/L", "refLow": 30, "refHigh": 300, "status": "low" },
        { "markerKey": "vitamin_d", "value": 18, "unit": "ng/mL", "refLow": 30, "refHigh": 60, "status": "low" },
        { "markerKey": "hemoglobin", "value": 14.8, "unit": "g/dL", "refLow": 13, "refHigh": 17, "status": "normal" },
        { "markerKey": "crp", "value": 0.6, "unit": "mg/L", "refLow": null, "refHigh": 5, "status": "normal" },
        { "markerKey": "tsh", "value": 2.1, "unit": "mUI/L", "refLow": 0.4, "refHigh": 4, "status": "normal" } ] },
      { "id": "t3", "sampledAt": "2026-06-03T08:00:00.000Z", "results": [
        { "markerKey": "ferritin", "value": 41, "unit": "µg/L", "refLow": 30, "refHigh": 300, "status": "normal" },
        { "markerKey": "vitamin_d", "value": 34, "unit": "ng/mL", "refLow": 30, "refHigh": 60, "status": "normal" },
        { "markerKey": "hemoglobin", "value": 15.1, "unit": "g/dL", "refLow": 13, "refHigh": 17, "status": "normal" } ] },
      { "id": "t2", "sampledAt": "2026-01-14T08:00:00.000Z", "results": [
        { "markerKey": "ferritin", "value": 54, "unit": "µg/L", "refLow": 30, "refHigh": 300, "status": "normal" },
        { "markerKey": "vitamin_d", "value": 22, "unit": "ng/mL", "refLow": 30, "refHigh": 60, "status": "low" } ] },
      { "id": "t1", "sampledAt": "2025-09-02T08:00:00.000Z", "results": [
        { "markerKey": "ferritin", "value": 62, "unit": "µg/L", "refLow": 30, "refHigh": 300, "status": "normal" } ] } ] }
    """#

    static let coachMemory = #"""
    { "activeId": "m1", "profileContext": "", "entries": [
      { "id": "m1", "type": "TRAVEL", "label": "Déplacement pro", "locationLabel": "Lyon",
        "startDate": "2026-11-17T00:00:00.000Z", "endDate": "2026-11-19T00:00:00.000Z",
        "note": "Sans vélo", "trainingConstraint": "REDUCED", "isActive": true },
      { "id": "m2", "type": "TRAVEL", "label": "Vacances", "locationLabel": "Lisbonne",
        "startDate": "2026-11-28T00:00:00.000Z", "endDate": "2026-12-02T00:00:00.000Z",
        "note": "Piscine sur place", "trainingConstraint": "FULL", "isActive": true },
      { "id": "m3", "type": "CONSTRAINT", "label": "Semaine chargée", "locationLabel": null,
        "startDate": "2026-12-08T00:00:00.000Z", "endDate": "2026-12-12T00:00:00.000Z",
        "note": "45 min par jour au plus", "trainingConstraint": "REDUCED", "isActive": true } ] }
    """#

    static let coachDayScores = #"""
{
  "type": "tool-explainDayScores",
  "state": "output-available",
  "input": {},
  "output": {
    "ok": true,
    "markdown": "## Scores du 2026-10-27",
    "schemaVersion": 1,
    "card": {
      "kind": "dayScores",
      "trainingDayId": "2026-10-27",
      "energyBank": { "value": 71, "typicalBaseline": 64 },
      "stress": 38,
      "targetBand": { "low": 8, "high": 12, "status": "within" },
      "readiness": 66
    }
  }
}
"""#

    static let coachTargetBand = #"""
{
  "type": "tool-explainTargetBand",
  "state": "output-available",
  "input": {},
  "output": {
    "ok": true,
    "markdown": "## Cible d'effort · 2026-10-27",
    "schemaVersion": 1,
    "card": {
      "kind": "targetBand",
      "trainingDayId": "2026-10-27",
      "band": { "low": 8, "high": 12, "status": "below" },
      "readiness": null
    }
  }
}
"""#

    static let coachSleepVsReadiness = #"""
{
  "type": "tool-compareSleepVsReadiness",
  "state": "output-available",
  "input": { "windowDays": 7 },
  "output": {
    "ok": true,
    "markdown": "## Sommeil vs forme (7 j)",
    "schemaVersion": 1,
    "card": {
      "kind": "sleepVsReadiness",
      "windowDays": 7,
      "points": [
        { "trainingDayId": "2026-10-26", "sleepMinutes": 410, "readiness": 62 },
        { "trainingDayId": "2026-10-27", "sleepMinutes": null, "readiness": 55 }
      ]
    }
  }
}
"""#

    static let savedMeals = #"""
    [ { "id": "s1", "name": "Petit-déjeuner de semaine", "kcal": 520, "protein": 22, "carbs": 78, "fat": 12, "items": [
          { "name": "Flocons d'avoine", "grams": 80, "kcal": 298, "protein": 11, "carbs": 48, "fat": 6 },
          { "name": "Banane", "grams": 120, "kcal": 107, "protein": 1, "carbs": 24, "fat": 0 },
          { "name": "Lait demi-écrémé", "grams": 250, "kcal": 115, "protein": 8, "carbs": 12, "fat": 4 } ] },
      { "id": "s2", "name": "Déjeuner au bureau", "kcal": 721, "protein": 55, "carbs": 68, "fat": 23, "items": [
          { "name": "Riz basmati, cuit", "grams": 220, "kcal": 286, "protein": 6, "carbs": 62, "fat": 1 },
          { "name": "Blanc de poulet grillé", "grams": 150, "kcal": 248, "protein": 46, "carbs": 0, "fat": 5 },
          { "name": "Courgettes sautées", "grams": 180, "kcal": 61, "protein": 3, "carbs": 6, "fat": 3 },
          { "name": "Huile d'olive", "grams": 14, "kcal": 126, "protein": 0, "carbs": 0, "fat": 14 } ] },
      { "id": "s3", "name": "Collation avant séance", "kcal": 268, "protein": 5, "carbs": 52, "fat": 4, "items": [
          { "name": "Banane", "grams": 120, "kcal": 107, "protein": 1, "carbs": 24, "fat": 0 },
          { "name": "Barre de céréales", "grams": 40, "kcal": 161, "protein": 4, "carbs": 28, "fat": 4 } ] } ]
    """#
}

struct DemoJournalAnalyses: JournalAnalysesServing {
    func journalAnalyses(token: String) async throws -> V1JournalAnalyses {
        try JSONDecoder().decode(V1JournalAnalyses.self, from: Data(DemoDataset.journalAnalyses.utf8))
    }
}

struct DemoSourcePrefs: SourcePrefsServing {
    func sourcePrefs(token: String) async throws -> V1SourcePrefsResponse {
        try JSONDecoder().decode(V1SourcePrefsResponse.self, from: Data(DemoDataset.sourcePrefs.utf8))
    }

    func updateSourcePrefs(_ action: SourcePrefsAction, dataClass: String, provider: String, token: String) async throws -> V1SourcePrefs {
        try await sourcePrefs(token: token).prefs
    }
}

struct DemoBloodTests: BloodTestServing {
    private struct Body: Decodable { let bloodTests: [V1BloodTest] }

    func bloodTests(token: String) async throws -> [V1BloodTest] {
        try JSONDecoder().decode(Body.self, from: Data(DemoDataset.bloodTests.utf8)).bloodTests
    }

    func deleteBloodTest(id: String, token: String) async throws {}
}

struct DemoCoachMemory: CoachMemoryServing {
    func snapshot(token: String) async throws -> CoachMemorySnapshot {
        try JSONDecoder().decode(CoachMemorySnapshot.self, from: Data(DemoDataset.coachMemory.utf8))
    }

    func saveProfileContext(_ context: String, token: String) async throws {}
    func createEntry(_ input: CreateCoachMemoryInput, token: String) async throws -> CoachMemoryEntry { throw SharpitAPIError.server }
    func updateEntry(id: String, _ input: CreateCoachMemoryInput, token: String) async throws -> CoachMemoryEntry { throw SharpitAPIError.server }
    func deleteEntry(id: String, token: String) async throws {}
}

struct DemoPrivacyConsents: PrivacyConsentServing {
    private static let consents = V1PrivacyConsents(
        termsAcceptedAt: .now, privacyAcceptedAt: .now, privacyVersion: "2026-11-03", healthDataConsentAt: .now,
        aiProcessingConsentAt: .now, unofficialProvidersAckAt: nil, currentPrivacyVersion: "2026-11-03"
    )

    func consents(token: String) async throws -> V1PrivacyConsents { Self.consents }
    func updateConsents(_ update: PrivacyConsentUpdate, token: String) async throws -> V1PrivacyConsents { Self.consents }
}
#endif
