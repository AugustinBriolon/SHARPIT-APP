import Foundation
import Testing
@testable import Sharpit

// MARK: - Records

private nonisolated let recordsJSON = """
{
  "prs": {
    "run": [
      {
        "key": "run-distance", "label": "Plus longue sortie",
        "entries": [
          { "rank": 2, "value": 18000, "displayValue": "18,0 km", "sublabel": null,
            "activityId": "a2", "date": "2026-08-01T07:00:00.000Z", "title": "Sortie longue" },
          { "rank": 1, "value": 21400, "displayValue": "21,4 km", "sublabel": "5:02/km",
            "activityId": "a1", "date": "2026-09-20T07:00:00.000Z", "title": "Semi" },
          { "rank": 3, "displayValue": "broken" }
        ]
      },
      { "key": "run-pace", "label": "Meilleure allure moyenne", "entries": [] }
    ],
    "bike": [
      {
        "key": "bike-np", "label": "Meilleure puissance normalisée",
        "entries": [
          { "rank": 1, "value": 265, "displayValue": "265 W", "sublabel": null,
            "activityId": null, "date": "2025-04-01T07:00:00Z", "title": null }
        ]
      }
    ],
    "swim": []
  },
  "powerCurve": [
    { "seconds": 5, "label": "5 s", "watts": 820, "activityId": "b1", "date": "2026-06-01T07:00:00.000Z", "title": "Sprints" },
    { "seconds": 1200, "label": "20 min", "watts": 278, "activityId": "b2", "date": "2026-07-01T07:00:00.000Z", "title": null }
  ],
  "runBests": [
    { "meters": 5000, "label": "5 km", "entries": [
      { "rank": 1, "value": 1260, "displayValue": "21:00", "sublabel": "4:12/km",
        "activityId": "a3", "date": "2026-09-01T07:00:00.000Z", "title": "Parkrun" }
    ] }
  ],
  "runEfforts": [{ "meters": 5000, "seconds": 1260 }],
  "bikeEfforts": [],
  "streamsAnalyzed": 180,
  "totalActivities": 214,
  "generatedAt": null
}
"""

private nonisolated func decodedRecords() throws -> V1Records {
    try JSONDecoder().decode(V1Records.self, from: Data(recordsJSON.utf8))
}

@Suite struct RecordsDecodingTests {
    @Test func readsEachSportBestFirstAndDropsWhatItCannot() throws {
        let records = try decodedRecords()
        let distance = try #require(records.prs.run.first)
        #expect(distance.label == "Plus longue sortie")
        #expect(distance.entries.map(\.rank) == [1, 2])
        #expect(distance.entries.first?.displayValue == "21,4 km")
        #expect(distance.entries.first?.sublabel == "5:02/km")
        #expect(records.prs.run[1].entries.isEmpty)
        #expect(records.categories(for: .bike).first?.entries.first?.activityId == nil)
        #expect(records.categories(for: .swim).isEmpty)
    }

    @Test func readsTheCurveTheBestTimesAndTheCounts() throws {
        let records = try decodedRecords()
        #expect(records.powerCurve.map(\.seconds) == [5, 1200])
        #expect(records.powerCurve.last?.watts == 278)
        #expect(records.runBests.first?.label == "5 km")
        #expect(records.runBests.first?.entries.first?.displayValue == "21:00")
        #expect(records.totalActivities == 214)
        #expect(records.streamsAnalyzed == 180)
        #expect(records.generatedAt == nil)
        #expect(!records.isEmpty)
    }

    @Test func anAthleteWithoutRecordsReadsEmpty() throws {
        let json = #"{ "prs": { "run": [], "bike": [], "swim": [] }, "powerCurve": [], "runBests": [], "streamsAnalyzed": 0, "totalActivities": 0, "generatedAt": null }"#
        let records = try JSONDecoder().decode(V1Records.self, from: Data(json.utf8))
        #expect(records.isEmpty)
    }
}

@Suite struct RecordsReadoutTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_791_000_000) // 2026-10-02

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    @Test func narratesHowOldARecordIsAsTheWebDoes() {
        #expect(RecordsReadout.narrative(daysAgo(0), now: now, calendar: utc) == "aujourd'hui")
        #expect(RecordsReadout.narrative(daysAgo(5), now: now, calendar: utc) == "il y a 5 jours")
        #expect(RecordsReadout.narrative(daysAgo(61), now: now, calendar: utc) == "il y a 2 mois")
        #expect(RecordsReadout.narrative(daysAgo(200), now: now, calendar: utc) == "record de la saison")
        #expect(RecordsReadout.narrative(daysAgo(800), now: now, calendar: utc) == "il y a 2 ans")
    }

    @Test func aRecordOfTheLastTwoWeeksIsNew() {
        #expect(RecordsReadout.isRecent(daysAgo(14), now: now, calendar: utc))
        #expect(!RecordsReadout.isRecent(daysAgo(15), now: now, calendar: utc))
    }

    @Test func wordsTheSummaryAndTheMeta() throws {
        let records = try decodedRecords()
        #expect(RecordsReadout.summary(records) == "Top 5 par catégorie sur 214 séances (180 avec données détaillées).")
        let best = try #require(records.prs.run.first?.entries.first)
        #expect(RecordsReadout.meta(best).hasPrefix("5:02/km · "))
        #expect(RecordsReadout.watts(277.6) == "278 W")
    }
}

// MARK: - Threshold estimates

private nonisolated let previewJSON = """
{
  "estimates": { "ftpW": 265, "ftpSource": "20 min", "runThresholdPaceSecPerKm": 252,
                 "swimCssSecPer100m": null, "windowDays": 120 },
  "current": { "ftpW": 250, "runThresholdPaceSecPerKm": null, "swimCssSecPer100m": 98 },
  "changes": [
    { "field": "ftpW", "label": "FTP vélo", "from": "250 W", "to": "265 W", "direction": "up" },
    { "field": "runThresholdPaceSecPerKm", "label": "Allure seuil", "from": "—", "to": "4:12/km", "direction": "set" },
    { "field": "lthr", "label": "Inconnu", "from": "1", "to": "2", "direction": "up" }
  ],
  "hasChanges": true
}
"""

private nonisolated func decodedPreview() throws -> V1ThresholdApplyPreview {
    try JSONDecoder().decode(V1ThresholdApplyPreview.self, from: Data(previewJSON.utf8))
}

@Suite struct ThresholdEstimateTests {
    @Test func readsTheProposalsItKnows() throws {
        let preview = try decodedPreview()
        #expect(preview.changes.map(\.field) == [.ftpW, .runThresholdPaceSecPerKm])
        #expect(preview.changes.first?.direction == .up)
        #expect(preview.changes.last?.from == "—")
        #expect(preview.estimates.windowDays == 120)
        #expect(preview.hasChanges)
    }

    @Test func theKeptProposalsBecomeTheProfileChange() throws {
        let preview = try decodedPreview()
        let patch = preview.patch(for: [.ftpW])
        #expect(patch.fields == ["ftpW": .number(265)])

        let both = preview.patch(for: [.ftpW, .runThresholdPaceSecPerKm, .swimCssSecPer100m])
        // The swim CSS is not proposed, so it is never written.
        #expect(both.fields == ["ftpW": .number(265), "runThresholdPaceSecPerKm": .number(252)])

        #expect(preview.removing([.ftpW]).changes.map(\.field) == [.runThresholdPaceSecPerKm])
    }

    @Test func wordsTheCard() {
        #expect(ThresholdSuggestionReadout.applyLabel(accepted: 2, offered: 2) == "Appliquer")
        #expect(ThresholdSuggestionReadout.applyLabel(accepted: 1, offered: 2) == "Appliquer (1)")
        #expect(ThresholdSuggestionReadout.applyLabel(accepted: 0, offered: 2) == "Appliquer")
        #expect(ThresholdSuggestionReadout.window(120) == "Capacité démontrée sur 120 jours — pas le record de toujours.")
        #expect(ThresholdSuggestionReadout.directionLabel(.down) == "Baisse")
    }

    @Test func aRefusalSaysWhyNothingWasWritten() {
        let unchanged = Data(#"{ "applied": false, "reason": "unchanged", "preview": {} }"#.utf8)
        #expect(AthleteProfileClient.applyRefusal(in: unchanged) == "Tes seuils sont déjà à jour.")
        let invalid = Data(#"{ "error": "Sélection invalide" }"#.utf8)
        #expect(AthleteProfileClient.applyRefusal(in: invalid) == "Sélection invalide")
    }

    @Test func theGarminImportSpeaksAsTheWebDoes() throws {
        let full = try JSONDecoder().decode(
            V1GarminThresholdImport.self,
            from: Data(#"{ "imported": true, "ftpW": 260, "maxHr": 188, "lthr": null, "runThresholdPaceSecPerKm": null, "vo2maxRunning": 55, "vo2maxCycling": null, "failedSources": [] }"#.utf8)
        )
        #expect(full.message == "Seuils importés depuis Garmin et enregistrés.")
        #expect(full.ftpW == 260)

        let partial = V1GarminThresholdImport(imported: true, failedSources: ["power-zones"])
        #expect(partial.message == "Import partiel : Garmin n'a pas répondu pour zones de puissance.")

        let nothing = V1GarminThresholdImport(imported: false)
        #expect(nothing.message == "Aucun seuil trouvé sur ton compte Garmin.")

        let unknown = V1GarminThresholdImport(imported: false, failedSources: ["user-settings", "heart-rate-zones"])
        #expect(unknown.message.hasPrefix("Garmin n'a pas répondu pour : réglages athlète, zones de FC."))
    }
}

private actor StubThresholdClient: AthleteProfileServing, ThresholdEstimating {
    private var stored: V1AthleteProfile
    private let preview: V1ThresholdApplyPreview
    private let refuses: Bool
    private(set) var appliedFields: [[V1ThresholdField]] = []

    init(_ profile: V1AthleteProfile, preview: V1ThresholdApplyPreview, refuses: Bool = false) {
        stored = profile
        self.preview = preview
        self.refuses = refuses
    }

    func athleteProfile(token _: String) async throws -> V1AthleteProfile { stored }

    func patchAthleteProfile(_ patch: AthleteProfilePatch, token _: String) async throws -> V1AthleteProfile {
        stored = stored.applying(patch)
        return stored
    }

    func thresholdHistory(token _: String) async throws -> [V1ThresholdSnapshot] { [] }

    func thresholdPreview(token _: String) async throws -> V1ThresholdApplyPreview {
        appliedFields.isEmpty ? preview : V1ThresholdApplyPreview(estimates: preview.estimates)
    }

    func applyThresholdEstimates(fields: [V1ThresholdField], token _: String) async throws {
        appliedFields.append(fields)
        if refuses { throw SharpitAPIError.message("Tes seuils sont déjà à jour.") }
        stored = stored.applying(preview.patch(for: Set(fields)))
    }

    func importGarminThresholds(token _: String) async throws -> V1GarminThresholdImport {
        V1GarminThresholdImport(imported: true)
    }

    func recordedFields() -> [[V1ThresholdField]] { appliedFields }
}

@MainActor
@Test func appliedEstimatesShowOnTheTapAndOnlyTheKeptOnesGoOut() async throws {
    let client = StubThresholdClient(V1AthleteProfile(ftpW: 250), preview: try decodedPreview())
    let profile = AthleteProfileStore(client: client, tokenProvider: { "t" })
    let suggestions = ThresholdSuggestionStore(client: client, tokenProvider: { "t" })
    await profile.load()
    await suggestions.loadPreview()

    suggestions.toggle(.runThresholdPaceSecPerKm)
    #expect(suggestions.accepted == [.ftpW])

    let write = suggestions.apply(to: profile)
    // Shown before the server has answered, and taken off the proposal.
    #expect(profile.profile.ftpW == 265)
    #expect(profile.profile.runThresholdPaceSecPerKm == nil)
    #expect(suggestions.offered.map(\.field) == [.runThresholdPaceSecPerKm])
    await write?.value

    #expect(await client.recordedFields() == [[.ftpW]])
    #expect(profile.profile.ftpW == 265)
    #expect(suggestions.revision == 1)
    #expect(suggestions.preview?.hasChanges == false)
}

@MainActor
@Test func aRefusedApplyIsSaidAndTheStoredValuesComeBack() async throws {
    let client = StubThresholdClient(V1AthleteProfile(ftpW: 250), preview: try decodedPreview(), refuses: true)
    let failures = SharpitWriteFailures()
    let profile = AthleteProfileStore(client: client, tokenProvider: { "t" })
    let suggestions = ThresholdSuggestionStore(client: client, tokenProvider: { "t" }, failures: failures)
    await profile.load()
    await suggestions.loadPreview()

    await suggestions.apply(to: profile)?.value

    #expect(failures.latest?.message == "Tes seuils sont déjà à jour.")
    #expect(profile.profile.ftpW == 250)
}

@MainActor
@Test func aGarminImportReadsTheProfileBack() async throws {
    let client = StubThresholdClient(V1AthleteProfile(ftpW: 250), preview: V1ThresholdApplyPreview())
    let profile = AthleteProfileStore(client: client, tokenProvider: { "t" })
    let suggestions = ThresholdSuggestionStore(client: client, tokenProvider: { "t" })

    await suggestions.importFromGarmin(into: profile)

    #expect(suggestions.importState == .done("Seuils importés depuis Garmin et enregistrés."))
    #expect(profile.phase == .loaded)
    #expect(suggestions.revision == 1)
}

// MARK: - Goal achievements

private nonisolated let achievementsJSON = """
[
  { "id": "ga1", "goalId": "g1", "activityId": "a1", "source": "auto", "value": 42195, "targetValue": 40000,
    "periodKey": "2026-W27", "achievedAt": "2026-07-05T12:00:00.000Z", "createdAt": "2026-07-05T12:00:00.000Z",
    "goal": { "id": "g1", "title": "40 km par semaine", "unit": "km", "metricKey": null, "kind": "METRIC" },
    "activity": { "id": "a1", "title": "Sortie longue", "type": "RUN", "date": "2026-07-05T08:00:00.000Z" } },
  { "id": "ga2", "goalId": "g2", "activityId": null, "source": "manual", "value": 2520, "targetValue": 2700,
    "periodKey": "_performance", "achievedAt": "2026-06-10T12:00:00Z",
    "goal": { "id": "g2", "title": "10 km en 45:00", "unit": "chrono",
              "metricKey": "{\\"v\\":1,\\"template\\":\\"performance\\",\\"sport\\":\\"RUN\\",\\"distanceM\\":10000}", "kind": "METRIC" },
    "activity": null },
  { "id": "broken" }
]
"""

@Suite struct GoalAchievementTests {
    @Test func readsTheHistoryAndDropsWhatItCannot() throws {
        let achievements = try JSONDecoder().decode(
            LossyRecordArray<V1GoalAchievement>.self,
            from: Data(achievementsJSON.utf8)
        ).items
        #expect(achievements.map(\.id) == ["ga1", "ga2"])
        #expect(achievements[0].activity?.id == "a1")
        #expect(achievements[1].activity == nil)
        #expect(achievements[1].isManual)
    }

    @Test func wordsAnAchievementAsTheWebDoes() throws {
        let achievements = try JSONDecoder().decode(
            LossyRecordArray<V1GoalAchievement>.self,
            from: Data(achievementsJSON.utf8)
        ).items
        let weekly = GoalAchievementReadout.line(achievements[0])
        #expect(weekly.hasPrefix("42,2 km · Semaine 27 · 2026 · "))

        let chrono = GoalAchievementReadout.line(achievements[1])
        #expect(chrono.hasPrefix("42:00 · "))
        #expect(chrono.hasSuffix(" · marqué manuellement"))
    }

    @Test func wordsPeriodsAndUnits() {
        #expect(GoalAchievementReadout.period("2026-07") == "juillet 2026")
        #expect(GoalAchievementReadout.period("2026") == "Année 2026")
        #expect(GoalAchievementReadout.period("_performance") == nil)
        #expect(GoalAchievementReadout.value(36_000, unit: "h", metricKey: nil) == "10 h")
        #expect(GoalAchievementReadout.value(9_000, unit: "h", metricKey: nil) == "2,5 h")
        #expect(GoalAchievementReadout.value(3, unit: "séances", metricKey: nil) == "3 séances")
        #expect(GoalAchievementReadout.value(1, unit: "séances", metricKey: nil) == "1 séance")
        #expect(GoalAchievementReadout.value(3_725, unit: "chrono", metricKey: nil) == "1:02:05")
        #expect(GoalAchievementReadout.value(nil, unit: "km", metricKey: nil) == "—")
    }
}
