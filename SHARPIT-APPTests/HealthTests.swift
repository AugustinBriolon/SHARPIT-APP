import Foundation
import HealthKit
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
    var workouts: [HealthWorkout] = []

    var isAvailable: Bool { available }
    func requestAuthorization() async throws { if let authorizationError { throw authorizationError } }
    func dailySummaries(since: Date) async -> [HealthDailySummary] { days }
    func workouts(endingIn interval: DateInterval) async -> [HealthWorkout] {
        workouts.filter { $0.end > interval.start && $0.end <= interval.end }
    }
}

private actor UploadRecorder: HealthUploadServing {
    private(set) var uploads = 0
    private(set) var workoutBatches: [[String]] = []
    var acceptsWorkouts = true
    var error: SharpitAPIError?

    func uploadWorkouts(_ workouts: [HealthWorkout], token: String) async throws -> HealthWorkoutUploadResult {
        workoutBatches.append(workouts.map(\.id))
        return HealthWorkoutUploadResult(acceptsWorkouts: acceptsWorkouts, imported: acceptsWorkouts ? workouts.count : 0)
    }

    func refuseWorkouts() { acceptsWorkouts = false }
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
    let apple = AppleHealthSource(reader: reader, client: recorder, defaults: defaults)
    apple.bind(userId: "user_1")
    return apple
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

/// The switch belongs to an account: a new account on the same iPhone starts with it off, and
/// the iPhone-wide value of earlier versions goes to the first account read.
@MainActor
@Test func eachAccountHasItsOwnAppleHealthSwitch() async throws {
    let defaults = try #require(UserDefaults(suiteName: "HealthTests-\(UUID().uuidString)"))
    defaults.set(true, forKey: AppleHealthSource.legacyEnabledKey)
    let apple = AppleHealthSource(reader: StubReader(), client: UploadRecorder(), defaults: defaults)

    apple.bind(userId: "user_main")
    #expect(apple.isEnabled)

    apple.bind(userId: "user_test")
    #expect(!apple.isEnabled)

    apple.bind(userId: "user_main")
    #expect(apple.isEnabled)
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

// MARK: - Workouts

private func workout(_ id: String, endingDaysAgo days: Double) -> HealthWorkout {
    let end = Date.now.addingTimeInterval(-days * 86_400)
    return HealthWorkout(
        id: id,
        type: .run,
        title: "Course à pied",
        start: end.addingTimeInterval(-3_600),
        end: end,
        durationSec: 3_600
    )
}

@MainActor
@Test func switchingOnSendsTheYearsWorkoutsOnceInBatches() async {
    let reader = StubReader()
    reader.workouts = (0..<7).map { workout("w\($0)", endingDaysAgo: Double(300 - $0 * 40)) }
        + [workout("old", endingDaysAgo: 400)]
    let recorder = UploadRecorder()
    let apple = source(reader, recorder)

    await apple.enable(token: { "t" })

    // A year back, not beyond it, each workout once.
    let sent = await recorder.workoutBatches.flatMap { $0 }
    #expect(sent == (0..<7).map { "w\($0)" })
    #expect(await recorder.workoutBatches.allSatisfy { $0.count <= AppleHealthSource.workoutBatch })

    // Sent is sent: the next sync starts where this one stopped.
    _ = await apple.send(token: { "t" })
    #expect(await recorder.workoutBatches.flatMap { $0 } == sent)
}

/// The server decides — a Garmin unlinked later means workouts are taken again — so a new
/// workout is still offered, but one refused is never read again.
@MainActor
@Test func aRefusedWorkoutIsNotSentAgain() async {
    let reader = StubReader()
    reader.workouts = [workout("a", endingDaysAgo: 3), workout("b", endingDaysAgo: 2)]
    let recorder = UploadRecorder()
    await recorder.refuseWorkouts()
    let apple = source(reader, recorder)

    await apple.enable(token: { "t" })
    reader.workouts.append(workout("c", endingDaysAgo: 0))
    _ = await apple.send(token: { "t" })

    #expect(await recorder.workoutBatches == [["a", "b"], ["c"]])
}

@Test func appleSportsMapOntoSharpItsOwn() {
    #expect(HealthWorkout.Sport(activityType: .running) == .run)
    #expect(HealthWorkout.Sport(activityType: .cycling) == .bike)
    #expect(HealthWorkout.Sport(activityType: .swimming) == .swim)
    #expect(HealthWorkout.Sport(activityType: .functionalStrengthTraining) == .strength)
    #expect(HealthWorkout.Sport(activityType: .walking) == .hike)
    #expect(HealthWorkout.Sport(activityType: .yoga) == .other)
    #expect(HealthWorkout.Sport.run.distanceType == .distanceWalkingRunning)
    #expect(HealthWorkout.Sport.strength.distanceType == nil)
}

@Test func theStreamsShareOneFiveSecondAxis() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let stream = try #require(HealthWorkoutStreamBuilder.build(
        start: start,
        durationSec: 12,
        heartRate: [(start.addingTimeInterval(1), 120), (start.addingTimeInterval(9), 150)],
        route: [
            HealthRoutePoint(date: start.addingTimeInterval(3), latitude: 48.85, longitude: 2.35, altitude: 35, speed: 3),
            HealthRoutePoint(date: start.addingTimeInterval(8), latitude: 48.8501, longitude: 2.35, altitude: 36, speed: 3.2),
        ]
    ))

    #expect(stream.time == [0, 5, 10])
    // A reading holds until the next one; nothing before the first.
    #expect(stream.heartrate == [nil, 120, 150])
    // Before the first fix, the route's start.
    #expect(stream.latlng == [[48.85, 2.35], [48.85, 2.35], [48.8501, 2.35]])
    #expect(stream.altitude == [35, 35, 36])
    let distance = try #require(stream.distance?.compactMap { $0 })
    #expect(distance[0] == 0 && distance[1] == 0)
    #expect(abs(distance[2] - 11.1) < 0.5)
}

@Test func aLongWorkoutStaysWithinTheServersCap() throws {
    let start = Date(timeIntervalSince1970: 0)
    let stream = try #require(HealthWorkoutStreamBuilder.build(
        start: start,
        durationSec: 20 * 3_600,
        heartRate: [(start, 110)],
        route: []
    ))
    #expect(stream.time.count <= HealthWorkoutStreamBuilder.maxPoints)
    #expect(stream.latlng == nil)
}

@Test func aWorkoutWithoutHeartRateOrRouteHasNoStream() {
    #expect(HealthWorkoutStreamBuilder.build(start: .now, durationSec: 600, heartRate: [], route: []) == nil)
}
