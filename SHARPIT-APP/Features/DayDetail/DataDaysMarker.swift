import Foundation
import Observation

/// Which days of a picker's history hold data — shared by the day screens and the journal.
///
/// The history is read in the route's 91-day windows. The window holding a day is read when
/// that day is asked about (the strip scrolled to an old week, the calendar opened on a month),
/// and the rest follow on their own, most recent first, in a task of the marker's own: a screen
/// left mid-way no longer cancels the reading for good, and a window that failed is read again
/// the next time it is needed.
@MainActor
@Observable
final class DataDaysMarker {
    /// True for a day with data, false for one read and empty. Absent while unknown.
    private(set) var byDay: [String: Bool] = [:]

    static let windowDays = 91

    @ObservationIgnored private let fetch: @Sendable (_ from: String, _ to: String, _ token: String) async throws -> [String]
    @ObservationIgnored private let tokenProvider: () async throws -> String
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// Windows by index back from today (0 holds today): read, or being read.
    @ObservationIgnored private var requested: Set<Int> = []
    @ObservationIgnored private var backfill: Task<Void, Never>?

    init(
        tokenProvider: @escaping () async throws -> String,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
        fetch: @escaping @Sendable (_ from: String, _ to: String, _ token: String) async throws -> [String]
    ) {
        self.tokenProvider = tokenProvider
        self.calendar = calendar
        self.now = now
        self.fetch = fetch
    }

    /// How many windows the picker's history spans.
    static var windowCount: Int {
        (SharpitWeeks.historyWeeks * 7 + windowDays - 1) / windowDays
    }

    subscript(dayId: String) -> Bool? { byDay[dayId] }

    /// What a payload or an edit already knows about a day — newer than any window read.
    func note(_ dayId: String, hasData: Bool) {
        byDay[dayId] = hasData
    }

    /// Reads the window holding `day` now, then every other window in the background.
    func ensure(around day: Date = .now) async {
        await read(window: window(containing: day))
        startBackfill()
    }

    /// Forgets everything: the next `ensure` reads the history again.
    func reset() {
        backfill?.cancel()
        backfill = nil
        requested = []
        byDay = [:]
    }

    private func startBackfill() {
        guard backfill == nil else { return }
        backfill = Task { [weak self] in
            for index in 0..<Self.windowCount {
                guard let self, !Task.isCancelled else { return }
                await self.read(window: index)
            }
            self?.backfill = nil
        }
    }

    private func window(containing day: Date) -> Int {
        let today = calendar.startOfDay(for: now())
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: today).day ?? 0
        return min(max(days, 0) / Self.windowDays, Self.windowCount - 1)
    }

    private func read(window index: Int) async {
        guard !requested.contains(index) else { return }
        requested.insert(index)
        let today = calendar.startOfDay(for: now())
        guard let end = calendar.date(byAdding: .day, value: -index * Self.windowDays, to: today),
              let start = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: end),
              let token = try? await tokenProvider(),
              let days = try? await fetch(TrainingDayId.today(now: start), TrainingDayId.today(now: end), token)
        else {
            // Read again the next time it is needed.
            requested.remove(index)
            return
        }
        var marks: [String: Bool] = [:]
        var day = start
        while day <= end {
            marks[TrainingDayId.today(now: day)] = false
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        for id in days { marks[id] = true }
        // What a payload or an edit said about a day stays: it is newer than the range read.
        byDay = marks.merging(byDay) { _, known in known }
    }
}
