import Foundation
import Testing
@testable import Sharpit

private actor Reads {
    private(set) var ranges: [String] = []
    var failNext = false

    func record(_ from: String, _ to: String) throws -> [String] {
        if failNext {
            failNext = false
            throw URLError(.notConnectedToInternet)
        }
        ranges.append("\(from)…\(to)")
        return [to]
    }

    func setFailNext() { failNext = true }
}

@MainActor
@Test func theWeekInViewIsReadFirstAndTheHistoryFollows() async throws {
    let reads = Reads()
    let now = ISO8601DateFormatter().date(from: "2026-09-30T10:00:00Z")!
    let marker = DataDaysMarker(tokenProvider: { "t" }, now: { now }) { from, to, _ in
        try await reads.record(from, to)
    }
    let oldWeek = Calendar.current.date(byAdding: .day, value: -400, to: now)!

    await marker.ensure(around: oldWeek)

    // The window holding the old week comes first, before the recent ones.
    let first = await reads.ranges.first
    #expect(first?.hasPrefix("2025-") == true)
    #expect(marker[TrainingDayId.today(now: oldWeek)] != nil)
}

@MainActor
@Test func aWindowThatFailedIsReadAgainWhenNeeded() async throws {
    let reads = Reads()
    await reads.setFailNext()
    let now = ISO8601DateFormatter().date(from: "2026-09-30T10:00:00Z")!
    let marker = DataDaysMarker(tokenProvider: { "t" }, now: { now }) { from, to, _ in
        try await reads.record(from, to)
    }
    let today = TrainingDayId.today(now: now)

    marker.reset()
    await marker.ensure(around: now)
    marker.reset()
    await marker.ensure(around: now)

    #expect(marker[today] == true)
}

@MainActor
@Test func whatAnEditSaidOutlivesTheRangeRead() async throws {
    let now = ISO8601DateFormatter().date(from: "2026-09-30T10:00:00Z")!
    let yesterday = TrainingDayId.today(now: Calendar.current.date(byAdding: .day, value: -1, to: now)!)
    let marker = DataDaysMarker(tokenProvider: { "t" }, now: { now }) { _, _, _ in [] }

    marker.note(yesterday, hasData: true)
    await marker.ensure(around: now)

    #expect(marker[yesterday] == true)
}
