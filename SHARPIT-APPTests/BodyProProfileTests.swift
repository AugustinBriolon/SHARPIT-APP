import Foundation
import Testing
@testable import Sharpit

// MARK: - /api/v1/body

private let overviewJSON = """
{
  "apiVersion": 1,
  "metrics": [
    { "key": "weight", "value": 72.4, "unit": "kg", "previous": 73.4, "deltaWindowDays": 7,
      "measuredAt": "2026-09-23T06:40:00.000Z", "source": "withings" },
    { "key": "hrv", "value": 50, "unit": "ms", "previous": 58, "deltaWindowDays": 7,
      "baseline": { "low": 55, "high": 70 }, "measuredAt": "2026-09-24T00:00:00.000Z", "source": "garmin" },
    { "key": "futureMetric", "value": 1, "unit": "x", "measuredAt": "2026-09-24T00:00:00.000Z", "source": "garmin" },
    { "key": "bmr", "value": 1712, "unit": "kcal", "measuredAt": "2026-09-23T06:40:00.000Z", "source": "withings" }
  ],
  "biologicalAge": null
}
"""

@Test func theOverviewSkipsAMetricThisBuildDoesNotKnow() throws {
    let overview = try JSONDecoder().decode(V1BodyOverview.self, from: Data(overviewJSON.utf8))

    #expect(overview.metrics.map(\.key) == [.weight, .hrv, .bmr])
    #expect(overview.biologicalAge == nil)
}

@Test func theOverviewReadsAsCorpsTiles() throws {
    let overview = try JSONDecoder().decode(V1BodyOverview.self, from: Data(overviewJSON.utf8))

    let metrics = CorpsReadout.metrics(from: overview)
    let weight = try #require(metrics.first { $0.key == .weight })
    let hrv = try #require(metrics.first { $0.key == .hrv })
    let bmr = try #require(metrics.first { $0.key == .bmr })

    #expect(weight.note == "−1,0 kg sur 7 j")
    #expect(weight.source == "Withings")
    #expect(hrv.note == "plage 55–70")
    #expect(hrv.tone == .belowRange)
    #expect(bmr.formattedValue == "1712")
    #expect(bmr.key.section == .composition)
}

@Test func theOverviewKeepsTheTilesTrend() throws {
    let overview = try JSONDecoder().decode(V1BodyOverview.self, from: Data(overviewJSON.utf8))
    let point = CorpsPoint(date: Date(timeIntervalSince1970: 1_800_000_000), value: 73)
    let local = [CorpsMetric(
        key: .weight, value: 73, measuredAt: nil, source: nil,
        series: [point], baseline: nil, note: nil, tone: .neutral
    )]

    let merged = CorpsReadout.merging(overview: overview, localSeries: local)

    #expect(merged.first { $0.key == .weight }?.series == [point])
    #expect(merged.first { $0.key == .weight }?.value == 72.4)
}

@Test func aSeriesReadsAsDays() throws {
    let json = #"{ "apiVersion": 1, "metric": "weight", "unit": "kg", "range": "30d", "points": [{ "date": "2026-09-20", "value": 72.9 }, { "date": "2026-09-23", "value": 72.4 }] }"#
    let series = try JSONDecoder().decode(V1BodySeries.self, from: Data(json.utf8))

    #expect(CorpsReadout.points(from: series).map(\.value) == [72.9, 72.4])
    #expect(CorpsRange.year.apiValue == "1y")
}

// MARK: - /api/v1/pro

@Test func proDecodesItsPerksAndSubscription() throws {
    let json = """
    {
      "apiVersion": 1, "tier": "PRO",
      "perks": [
        { "id": "weekly-review", "title": "Bilan hebdomadaire", "description": "…", "status": "pro" },
        { "id": "watch-push", "title": "Envoi vers la montre", "description": "…", "status": "included" },
        { "id": "odd", "title": "?", "description": "?", "status": "someday" }
      ],
      "subscription": { "status": "active", "source": "apple", "renewsAt": "2026-10-24T08:00:00.000Z",
                        "expiresAt": "2026-10-24T08:00:00.000Z", "willRenew": true }
    }
    """
    let pro = try JSONDecoder().decode(V1Pro.self, from: Data(json.utf8))

    #expect(pro.isPro)
    #expect(pro.perks.map(\.id) == ["weekly-review", "watch-push"])
    #expect(pro.subscription?.source == "apple")
    #expect(ProReadout.status(pro.subscription, isPro: true).hasPrefix("Renouvellement le "))
}

@Test func proStatusSaysWhatTheAthleteHas() {
    #expect(ProReadout.status(nil, isPro: false) == "Version gratuite")
    #expect(ProReadout.status(nil, isPro: true) == "Accès Pro offert")
    #expect(ProReadout.status(V1ProSubscription(status: "grace_period", source: "apple"), isPro: true)
        == "Paiement en attente — l'accès est maintenu")
}

// MARK: - Profile

@Test func theProfileDecodesSexAndNotificationPrefs() throws {
    let json = #"{ "sex": "female", "notificationPrefs": { "version": 1, "morningVerdict": false, "morningTime": null, "weeklyReview": true, "sessionReminder": true, "syncAlerts": false } }"#
    let profile = try JSONDecoder().decode(V1AthleteProfile.self, from: Data(json.utf8))

    #expect(profile.sex == .female)
    #expect(profile.notificationPrefs?.morningVerdict == false)
    #expect(profile.notificationPrefs?.syncAlerts == false)
}

@Test func aNotificationSwitchSendsOnlyItself() {
    var patch = AthleteProfilePatch()

    patch.setNotificationPrefs(["weeklyReview": .bool(false)])

    #expect(patch.fields["notificationPrefs"] == .object(["version": .number(1), "weeklyReview": .bool(false)]))
}

@Test func clearingTheSexSendsNull() {
    var patch = AthleteProfilePatch()

    patch.setSex(nil)

    #expect(patch.fields["sex"] == .null)
}

@Test func sleepTargetsReadInHours() {
    #expect(SleepTargetFormat.duration(450) == "7 h 30")
    #expect(SleepTargetFormat.duration(480) == "8 h")
    #expect(SleepTargetFormat.short(510) == "8h30")
}
