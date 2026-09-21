import Foundation
import Testing
@testable import Sharpit

private let sleepJSON = """
{
  "apiVersion": 1, "trainingDayId": "2026-09-21", "nightStatus": "present", "empty": null,
  "score": 82, "adequacy": { "key": "ADEQUATE", "label": "Sommeil suffisant" },
  "durationMin": 452, "targetMin": 480, "targetDeltaMin": -28, "delta7dMin": 18,
  "stages": { "deepMin": 80, "remMin": 110, "lightMin": 240, "awakeMin": 22 },
  "bedtimeMin": 1390, "wakeMin": 422,
  "breakdown": { "durationScore": 88, "architectureScore": 74.5, "restorativeRatio": 0.42 },
  "averages": { "score": 76, "durationMin": 434.4, "deepPct": 17.2, "remPct": 23, "nights": 7 },
  "regularityMin": 35.4, "recommendedBedtimeMin": 1350, "recommendedDurationMin": 495,
  "debt7Min": 96, "debt14Min": 150, "recoveryNote": null,
  "history": [{ "date": "2026-09-20", "minutes": null }, { "date": "2026-09-21", "minutes": 452 }],
  "insights": [{ "tone": "moderate", "title": "Dette légère", "detail": "Couche-toi plus tôt." }],
  "confidencePct": 74
}
"""

private func decodedSleep(_ json: String = sleepJSON) throws -> V1SleepResponse {
    try JSONDecoder().decode(V1SleepResponse.self, from: Data(json.utf8))
}

// MARK: - Contract

/// Averages and regularity are computed server-side and may arrive fractional; one such
/// value must not fail the whole night.
@Test func sleepDecodesFractionalMeasures() throws {
    let sleep = try decodedSleep()
    #expect(sleep.regularityMin == 35.4)
    #expect(sleep.averages.durationMin == 434.4)
    #expect(sleep.adequacy.key == .adequate)
    #expect(sleep.history.count == 2)
    #expect(sleep.insights.first?.tone == .moderate)
}

@Test func anUnknownAdequacyOrToneDegradesInsteadOfFailing() throws {
    let json = sleepJSON
        .replacingOccurrences(of: "\"ADEQUATE\"", with: "\"SOMETHING_NEW\"")
        .replacingOccurrences(of: "\"moderate\"", with: "\"sparkly\"")
    let sleep = try decodedSleep(json)
    #expect(sleep.adequacy.key == .unknown)
    #expect(sleep.insights.first?.tone == .neutral)
}

// MARK: - Readout

@Test func sleepDurationsReadInHoursAndMinutes() {
    #expect(SleepReadout.duration(452) == "7 h 32")
    #expect(SleepReadout.duration(480) == "8 h")
    #expect(SleepReadout.duration(45) == "45 min")
    #expect(SleepReadout.duration(nil) == "—")
}

@Test func sleepDeltasCarryTheirSignAndHideZero() {
    #expect(SleepReadout.delta(18) == "+18 min")
    #expect(SleepReadout.delta(-65) == "−1 h 05")
    #expect(SleepReadout.delta(0) == nil)
    #expect(SleepReadout.delta(nil) == nil)
}

@Test func bedtimesPastMidnightWrapOnTheClock() {
    #expect(SleepReadout.clock(1390) == "23:10")
    #expect(SleepReadout.clock(1470) == "00:30")
    #expect(SleepReadout.clock(422) == "07:02")
}

@Test func timeInBedSpansMidnight() {
    #expect(SleepReadout.timeInBed(bedtime: 1390, wake: 422) == 472)
    #expect(SleepReadout.timeInBed(bedtime: 30, wake: 450) == 420)
    #expect(SleepReadout.timeInBed(bedtime: nil, wake: 422) == nil)
}

@Test func theSleepBankReadsDebtAsAWithdrawal() {
    #expect(SleepReadout.bankBalance(debtMin: 96) == "−1 h 36")
    #expect(SleepReadout.bankBalance(debtMin: 0) == "À l'équilibre")
    #expect(SleepReadout.bankBalance(debtMin: nil) == "—")
}

/// Time awake is not sleep: the structure splits the sleep itself.
@Test func stageSharesAddUpAndSkipAnEmptyNight() throws {
    let shares = try #require(SleepReadout.stageShares(decodedSleep().stages))
    #expect(shares.map(\.stage) == [.deep, .rem, .light])
    #expect(abs(shares.map(\.share).reduce(0, +) - 1) < 0.000_1)
    #expect(SleepReadout.stageShares(V1SleepStages(deepMin: nil, remMin: nil, lightMin: nil, awakeMin: nil)) == nil)
}

// MARK: - Store

private struct StubSleep: SleepServing {
    var result: Result<V1SleepResponse, SharpitAPIError>

    func sleep(trainingDayId: String, token: String) async throws -> V1SleepResponse {
        try result.get()
    }
}

@MainActor
private func sleepStore(_ client: StubSleep) -> DayResourceStore<V1SleepResponse> {
    DayResourceStore(failureMessage: "failed", tokenProvider: { "t" }) {
        try await client.sleep(trainingDayId: $0, token: $1)
    }
}

@MainActor
@Test func aNightWithAnEmptyStateReadsAsEmpty() async throws {
    let json = sleepJSON.replacingOccurrences(
        of: "\"empty\": null",
        with: "\"empty\": { \"title\": \"Données de sommeil indisponibles.\", \"message\": null }"
    )
    let store = sleepStore(StubSleep(result: .success(try decodedSleep(json))))
    await store.load()
    #expect(store.phase == .empty(V1DayEmpty(title: "Données de sommeil indisponibles.", message: nil)))
}

@MainActor
@Test func anExpiredSessionReadsAsUnauthorized() async {
    let store = sleepStore(StubSleep(result: .failure(.unauthorized)))
    await store.load()
    #expect(store.phase == .unauthorized)
}

@MainActor
@Test func aNightLoads() async throws {
    let store = sleepStore(StubSleep(result: .success(try decodedSleep())))
    await store.load()
    guard case .loaded(let sleep) = store.phase else {
        Issue.record("expected a loaded night")
        return
    }
    #expect(sleep.score == 82)
}

// MARK: - Picking another day

private actor DayRecorder {
    private(set) var requested: [String] = []
    func record(_ day: String) { requested.append(day) }
}

@MainActor
@Test func pickingADayLoadsThatDay() async throws {
    let recorder = DayRecorder()
    let payload = try decodedSleep()
    let store = DayResourceStore<V1SleepResponse>(
        failureMessage: "failed",
        tokenProvider: { "t" },
        day: try #require(TrainingDayId.date("2026-09-21"))
    ) { day, _ in
        await recorder.record(day)
        return payload
    }
    await store.load()
    await store.select(try #require(TrainingDayId.date("2026-09-18")))

    #expect(await recorder.requested == ["2026-09-21", "2026-09-18"])
    #expect(store.isSwitchingDay == false)
}

/// A failed day must not leave the previous day's night under the new date.
@MainActor
@Test func aFailedDaySwitchSaysSoInsteadOfShowingTheOldDay() async throws {
    let payload = try decodedSleep()
    let store = DayResourceStore<V1SleepResponse>(
        failureMessage: "failed",
        tokenProvider: { "t" },
        day: try #require(TrainingDayId.date("2026-09-21"))
    ) { day, _ in
        if day == "2026-09-18" { throw SharpitAPIError.server }
        return payload
    }
    await store.load()
    await store.select(try #require(TrainingDayId.date("2026-09-18")))

    #expect(store.phase == .failed("failed"))
}

/// The picker marks each day from the histories already loaded, without another request.
@MainActor
@Test func loadedHistoryTellsWhichDaysHoldData() async throws {
    let payload = try decodedSleep()
    let store = DayResourceStore<V1SleepResponse>(
        failureMessage: "failed",
        tokenProvider: { "t" },
        day: try #require(TrainingDayId.date("2026-09-21"))
    ) { _, _ in payload }
    await store.load()

    #expect(store.hasData(on: try #require(TrainingDayId.date("2026-09-21"))) == true)
    #expect(store.hasData(on: try #require(TrainingDayId.date("2026-09-20"))) == false)
    #expect(store.hasData(on: try #require(TrainingDayId.date("2026-09-01"))) == nil)
}
