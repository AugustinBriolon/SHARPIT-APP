import Foundation
import Testing
@testable import Sharpit

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private func sample(
    _ start: Date,
    _ end: Date,
    _ stage: HealthSleepSample.Stage,
    _ source: String = "Connect"
) -> HealthSleepSample {
    HealthSleepSample(start: start, end: end, stage: stage, source: source)
}

// MARK: - Coverage

@Test func coverageGradesEachSignalAndNamesGarmin() {
    let rows = HealthCoverage.rows(
        readings: [
            .sleep: HealthSignalReading(sources: ["Connect"], days: Set((1...14).map { "d\($0)" })),
            .restingHeartRate: HealthSignalReading(sources: ["Connect"], days: ["d1", "d2"]),
        ],
        windowDays: 14
    )
    let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.signal, $0) })
    #expect(byId[.sleep]?.verdict == .covered)
    #expect(byId[.sleep]?.fromGarmin == true)
    #expect(byId[.restingHeartRate]?.verdict == .partial)
    #expect(byId[.heartRateVariability]?.verdict == .missing)
    #expect(byId[.bodyBattery]?.verdict == .noEquivalent)
}

// MARK: - Nights

@Test func aNightIsBuiltFromItsStagesAndDatedOnWaking() throws {
    let nights = HealthDailySummary.nights(from: [
        sample(at(20, 23, 10), at(21, 0, 30), .core),
        sample(at(21, 0, 30), at(21, 1, 40), .deep),
        sample(at(21, 1, 40), at(21, 1, 50), .awake),
        sample(at(21, 1, 50), at(21, 7, 0), .rem),
    ], calendar: calendar)
    let night = try #require(nights.first)
    #expect(nights.count == 1)
    #expect(night.day == "2026-09-21")
    #expect(Int(night.asleepMinutes) == 460)
}

/// Garmin and an Apple Watch both writing the same night must not count it twice.
@Test func twoWritersOfTheSameNightKeepTheFullerOne() throws {
    let nights = HealthDailySummary.nights(from: [
        sample(at(20, 23, 0), at(21, 7, 0), .asleep, "Connect"),
        sample(at(20, 23, 30), at(21, 6, 0), .asleep, "Apple Watch"),
    ], calendar: calendar)
    let night = try #require(nights.first)
    #expect(Set(night.samples.map(\.source)) == ["Connect"])
    #expect(Int(night.asleepMinutes) == 480)
}

/// An afternoon nap is a separate sleep and does not become the day's night.
@Test func aNapDoesNotReplaceTheNight() throws {
    let nights = HealthDailySummary.nights(from: [
        sample(at(20, 23, 0), at(21, 6, 30), .asleep),
        sample(at(21, 14, 0), at(21, 14, 40), .asleep),
    ], calendar: calendar)
    #expect(nights.count == 1)
    #expect(try Int(#require(nights.first).asleepMinutes) == 450)
}

@Test func daySummariesCarryTheNightAndTheDaysValues() throws {
    let days = HealthDailySummary.merge(
        nights: [
            sample(at(20, 23, 10), at(21, 1, 0), .deep),
            sample(at(21, 1, 0), at(21, 7, 0), .core),
        ],
        restingHeartRate: ["2026-09-21": 48.4],
        hrv: [:],
        steps: ["2026-09-21": 9_120.6],
        activeEnergy: [:],
        bodyMass: ["2026-09-20": 71.26],
        calendar: calendar
    )
    #expect(days.map(\.date) == ["2026-09-20", "2026-09-21"])
    let today = try #require(days.last)
    #expect(today.sleepMinutes == 470)
    #expect(today.sleepDeepMin == 110)
    #expect(today.sleepLightMin == 360)
    #expect(today.sleepBedtimeMin == 23 * 60 + 10)
    #expect(today.sleepWakeMin == 7 * 60)
    #expect(today.restingHr == 48)
    #expect(today.totalSteps == 9_121)
    #expect(days.first?.weightKg == 71.3)
}

// MARK: - Sending

private final class StubReader: HealthReading, @unchecked Sendable {
    var available = true
    var authorizationError: Error?
    var days: [HealthDailySummary] = [HealthDailySummary(date: "2026-09-21")]

    var isAvailable: Bool { available }
    func requestAuthorization() async throws { if let authorizationError { throw authorizationError } }
    func reading(for signal: HealthSignal, since: Date) async -> HealthSignalReading { .empty }
    func dailySummaries(since: Date) async -> [HealthDailySummary] { days }
}

private actor UploadRecorder: HealthUploadServing {
    private(set) var uploads = 0
    var error: SharpitAPIError?
    func uploadHealth(_ days: [HealthDailySummary], token: String) async throws -> Int {
        uploads += 1
        if let error { throw error }
        return days.count
    }
    func fail(with error: SharpitAPIError) { self.error = error }
}

@MainActor
private func source(_ reader: StubReader, _ recorder: UploadRecorder) -> AppleHealthSource {
    let defaults = UserDefaults(suiteName: "HealthTests-\(UUID().uuidString)")!
    return AppleHealthSource(reader: reader, client: recorder, defaults: defaults)
}

@MainActor
@Test func nothingIsSentUntilAppleHealthIsTurnedOn() async {
    let recorder = UploadRecorder()
    let apple = source(StubReader(), recorder)
    #expect(await apple.send(token: { "t" }) == false)
    #expect(await recorder.uploads == 0)
}

@MainActor
@Test func turningAppleHealthOnSendsTheWeek() async {
    let recorder = UploadRecorder()
    let reader = StubReader()
    var days = HealthDailySummary(date: "2026-09-21")
    days.restingHr = 48
    reader.days = [days]
    let apple = source(reader, recorder)
    await apple.enable(token: { "t" })
    #expect(apple.isEnabled)
    #expect(await recorder.uploads == 1)
    #expect(apple.lastSentAt != nil)
}

@MainActor
@Test func aRefusedAccessLeavesAppleHealthOff() async {
    let reader = StubReader()
    reader.authorizationError = SharpitAPIError.unauthorized
    let apple = source(reader, UploadRecorder())
    await apple.enable(token: { "t" })
    #expect(apple.isEnabled == false)
    #expect(apple.state == .failed("Accès à Apple Santé refusé."))
}

@MainActor
@Test func aRateLimitedSendStaysQuiet() async {
    let recorder = UploadRecorder()
    await recorder.fail(with: .rateLimited)
    let apple = source(StubReader(), recorder)
    await apple.enable(token: { "t" })
    #expect(apple.state == .idle)
}

@MainActor
@Test func theDiagnosticSaysWhenHealthIsUnavailable() async {
    let reader = StubReader()
    reader.available = false
    let store = HealthCoverageStore(reader: reader)
    await store.run()
    #expect(store.phase == .unavailable)
}
