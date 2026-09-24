import Foundation
import Testing
@testable import Sharpit

// MARK: - Calendar marks

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func day(_ month: Int, _ day: Int, hour: Int = 9) -> Date {
    paris.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

@Test func anActivityOutranksThePlanOnItsDay() {
    let marks = PlanStore.calendarMarks(
        planned: [day(3, 10), day(3, 12), day(9, 30)],
        activities: [day(3, 10, hour: 18), day(1, 4)],
        calendar: paris,
        now: day(9, 24)
    )

    #expect(marks[paris.startOfDay(for: day(3, 10))] == .filled)
    // Planned, gone by, nothing recorded.
    #expect(marks[paris.startOfDay(for: day(3, 12))] == .muted)
    // Planned and still ahead.
    #expect(marks[paris.startOfDay(for: day(9, 30))] == .ring)
    // Older than any plan still shows: the history is what the calendar is for.
    #expect(marks[paris.startOfDay(for: day(1, 4))] == .filled)
    #expect(marks.count == 4)
}

// MARK: - Garmin history import

private actor StubHistoryClient: GarminHistoryImporting {
    private(set) var runs = 0
    private let result: Result<Int, SharpitAPIError>

    init(_ result: Result<Int, SharpitAPIError>) { self.result = result }

    func importFullGarminHistory(token _: String) async throws -> Int {
        runs += 1
        return try result.get()
    }
}

private nonisolated struct StubStatusClient: SyncServing {
    let providers: [String]

    func syncStatus(token _: String) async throws -> V1SyncStatus {
        V1SyncStatus(
            lastSyncAt: nil,
            providers: providers.map { V1SyncProvider(key: $0, label: $0, lastSyncAt: nil) }
        )
    }

    func sync(token: String) async throws -> V1SyncStatus { try await syncStatus(token: token) }
}

private func freshDefaults(_ name: String) throws -> UserDefaults {
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Test func theWholeHistoryIsImportedOnceThenNeverAgain() async throws {
    let defaults = try freshDefaults("history-once")
    let client = StubHistoryClient(.success(412))
    let importer = GarminHistoryImport(
        client: client,
        statusClient: StubStatusClient(providers: ["garmin"]),
        defaults: defaults
    )

    await importer.runIfNeeded(userId: "u1") { "t" }
    #expect(importer.state == .finished(imported: 412))
    #expect(importer.completedAt != nil)

    await importer.runIfNeeded(userId: "u1") { "t" }
    #expect(await client.runs == 1)
}

@MainActor
@Test func anInterruptedImportRunsAgainNextTime() async throws {
    let defaults = try freshDefaults("history-retry")
    let failing = GarminHistoryImport(
        client: StubHistoryClient(.failure(.server)),
        statusClient: StubStatusClient(providers: ["garmin"]),
        defaults: defaults
    )
    await failing.runIfNeeded(userId: "u2") { "t" }
    #expect(failing.state == .failed)
    #expect(!failing.isDone(for: "u2"))

    let retry = StubHistoryClient(.success(0))
    let next = GarminHistoryImport(
        client: retry,
        statusClient: StubStatusClient(providers: ["garmin"]),
        defaults: defaults
    )
    await next.runIfNeeded(userId: "u2") { "t" }
    #expect(await retry.runs == 1)
    #expect(next.isDone(for: "u2"))
}

@MainActor
@Test func noGarminMeansNoImport() async throws {
    let client = StubHistoryClient(.success(3))
    let importer = GarminHistoryImport(
        client: client,
        statusClient: StubStatusClient(providers: []),
        defaults: try freshDefaults("history-no-garmin")
    )

    await importer.runIfNeeded(userId: "u3") { "t" }

    #expect(importer.state == .idle)
    #expect(await client.runs == 0)
}

@MainActor
@Test func theSourcesButtonImportsAgainAfterAFinishedRun() async throws {
    let defaults = try freshDefaults("history-forced")
    let client = StubHistoryClient(.success(3))
    let importer = GarminHistoryImport(
        client: client,
        statusClient: StubStatusClient(providers: ["garmin"]),
        defaults: defaults
    )

    await importer.runIfNeeded(userId: "u1") { "t" }
    await importer.runIfNeeded(userId: "u1") { "t" }
    #expect(await client.runs == 1)

    await importer.importAll(userId: "u1") { "t" }
    #expect(await client.runs == 2)
    #expect(importer.state == .finished(imported: 3))
}

@MainActor
@Test func theHistoryRowSaysHowTheLastRunWent() {
    #expect(ConnectionsReadout.garminHistory(.finished(imported: 0)) == "Historique à jour")
    #expect(ConnectionsReadout.garminHistory(.finished(imported: 1)) == "1 activité importée")
    #expect(ConnectionsReadout.garminHistory(.finished(imported: 12)) == "12 activités importées")
}

// MARK: - Activity disk cache

@Test func aStreamStaysFreshAndADetailExpires() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    #expect(ActivityCachePolicy.isFresh(.stream, savedAt: now.addingTimeInterval(-90 * 86_400), now: now))
    #expect(ActivityCachePolicy.isFresh(.detail, savedAt: now.addingTimeInterval(-3600), now: now))
    #expect(!ActivityCachePolicy.isFresh(.detail, savedAt: now.addingTimeInterval(-13 * 3600), now: now))
}

@Test func theDiskCacheKeepsTheServersBytes() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "activity-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
    let cache = ActivityDiskCache(directory: directory)
    defer { cache.removeAll() }
    let bytes = Data(#"{"id":"a/1"}"#.utf8)

    cache.write(bytes, .stream, id: "a/1")

    #expect(cache.read(.stream, id: "a/1")?.data == bytes)
    #expect(cache.read(.detail, id: "a/1") == nil)
    cache.remove(.stream, id: "a/1")
    #expect(cache.read(.stream, id: "a/1") == nil)
}

@Test func aPlannedBreakdownSurvivesTheDiskAndIsAlwaysAskedAgain() throws {
    let breakdown = V1PlannedSessionBreakdown(
        steps: [
            V1PlannedSessionStep(key: "warmup", label: "Échauffement", detail: "15 min"),
            V1PlannedSessionStep(key: "main", label: "4 × 1 km", target: "3:40/km", repeatCount: 4),
        ],
        derived: true
    )
    let data = try JSONEncoder().encode(breakdown)

    #expect(try JSONDecoder().decode(V1PlannedSessionBreakdown.self, from: data) == breakdown)
    #expect(String(decoding: data, as: UTF8.self).contains(#""repeat":4"#))
    #expect(!ActivityCachePolicy.isFresh(.plannedBreakdown, savedAt: Date()))
}
