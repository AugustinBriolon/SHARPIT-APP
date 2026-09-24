import Observation
import SwiftUI

/// The plan, one week per page.
///
/// Weeks are addressed by an offset from the current one rather than by a mutable start
/// date. A page in the pager is then a stable identity — page 3 is always three weeks
/// ahead — and swiping, tapping "Aujourd'hui" and picking a date in the calendar all
/// reduce to one operation: set `selectedOffset`.
@MainActor
@Observable
final class PlanStore {
    enum Phase {
        case loading
        case loaded([PlanEntry])
        case error(String)
        case unauthorized
    }

    /// Half a year either side of today. Bounded so the pager stays a fixed set of pages
    /// instead of an infinite one, which is where paging bugs live.
    static let offsets: ClosedRange<Int> = -26...26

    let weekCalendar = SharpitWeeks(offsets: PlanStore.offsets)

    var selectedOffset = 0
    /// A day the strip asked the list to scroll to. Consumed by the visible page.
    var scrollTarget: Date?

    private var weeks: [Int: Phase] = [:]

    private let client: any PlannedSessionServing
    private let activityClient: any ActivityServing
    private let tokenProvider: () async throws -> String
    private var calendar: Calendar { weekCalendar.calendar }

    init(
        client: any PlannedSessionServing,
        activityClient: any ActivityServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.client = client
        self.activityClient = activityClient
        self.tokenProvider = tokenProvider
    }

    // MARK: - Weeks

    func weekStart(forOffset offset: Int) -> Date {
        weekCalendar.weekStart(forOffset: offset)
    }

    /// The offset of the week containing `day`, clamped to the pager's range.
    func offset(forWeekContaining day: Date) -> Int {
        weekCalendar.offset(forWeekContaining: day)
    }

    var weekStart: Date { weekStart(forOffset: selectedOffset) }

    func weekDays(forOffset offset: Int) -> [Date] {
        weekCalendar.weekDays(forOffset: offset)
    }

    var weekDays: [Date] { weekDays(forOffset: selectedOffset) }

    var isCurrentWeek: Bool { selectedOffset == 0 }

    /// The range the calendar sheet may pick from — the pager's own bounds.
    var selectableDates: ClosedRange<Date> { weekCalendar.selectableDates }

    // MARK: - Navigation

    func showWeek(containing day: Date) {
        selectedOffset = offset(forWeekContaining: day)
    }

    func goToToday() {
        selectedOffset = 0
    }

    // MARK: - Reading

    func phase(forOffset offset: Int) -> Phase {
        weeks[offset] ?? .loading
    }

    var phase: Phase { phase(forOffset: selectedOffset) }

    func entries(on day: Date, from entries: [PlanEntry]) -> [PlanEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// What the strip shows for `day`, if that day's week has loaded.
    ///
    /// Takes the offset rather than reading the selection, because the strip pages the
    /// same weeks as the content: a neighbouring page must draw its own dots while it
    /// scrolls past, not the selected week's.
    func status(on day: Date, offset: Int) -> PlanDayStatus? {
        guard case .loaded(let entries) = phase(forOffset: offset) else { return nil }
        return PlanDayStatus.status(of: self.entries(on: day, from: entries))
    }

    func status(on day: Date) -> PlanDayStatus? {
        status(on: day, offset: selectedOffset)
    }

    /// Next actionable session in the visible week: today or later, and still to be done.
    /// Never highlights the past, and never a session already absorbed by an activity.
    func focusSession(from entries: [PlanEntry], now: Date = Date()) -> V1PlannedSessionItem? {
        let startOfToday = calendar.startOfDay(for: now)
        return entries
            .compactMap { entry -> V1PlannedSessionItem? in
                guard case .planned(let session) = entry else { return nil }
                return session
            }
            .filter { $0.date >= startOfToday }
            .sorted { lhs, rhs in
                if calendar.isDateInToday(lhs.date) != calendar.isDateInToday(rhs.date) {
                    return calendar.isDateInToday(lhs.date)
                }
                return lhs.date < rhs.date
            }
            .first
    }

    // MARK: - Loading

    /// Loads the selected week, then its neighbours, so a swipe lands on content instead
    /// of a skeleton.
    func loadAroundSelection() async {
        await load(offset: selectedOffset)
        for neighbour in [selectedOffset - 1, selectedOffset + 1] where Self.offsets.contains(neighbour) {
            await load(offset: neighbour)
        }
    }

    func load() async {
        await reload()
    }

    /// Re-fetches the target date's week and selection forcefully, clearing client caches.
    func reload(around date: Date? = nil) async {
        await activityClient.invalidateActivities()
        let targetOffset = date.map { offset(forWeekContaining: $0) } ?? selectedOffset
        await load(offset: targetOffset, force: true)
        if targetOffset != selectedOffset {
            await load(offset: selectedOffset, force: true)
        }
        for neighbour in [targetOffset - 1, targetOffset + 1] where Self.offsets.contains(neighbour) {
            await load(offset: neighbour, force: true)
        }
    }

    /// Marks for the month view, across every week the pager holds — not only the weeks
    /// already loaded: a day with an activity is filled, a planned day still ahead is a
    /// ring, a planned day gone by without one is muted. The same shapes as the strip.
    func calendarMarks(now: Date = Date()) async -> [Date: SharpitCalendarMark] {
        guard let token = try? await tokenProvider() else { return [:] }
        let range = selectableDates
        async let planned = try? client.plannedSessions(from: range.lowerBound, to: range.upperBound, token: token)
        async let recorded = try? activityClient.activities(token: token)
        return Self.calendarMarks(
            planned: (await planned ?? []).map(\.date),
            activities: (await recorded ?? []).map(\.date),
            calendar: calendar,
            now: now
        )
    }

    nonisolated static func calendarMarks(
        planned: [Date],
        activities: [Date],
        calendar: Calendar,
        now: Date
    ) -> [Date: SharpitCalendarMark] {
        let today = calendar.startOfDay(for: now)
        var marks: [Date: SharpitCalendarMark] = [:]
        for date in planned {
            let day = calendar.startOfDay(for: date)
            marks[day] = day >= today ? .ring : .muted
        }
        for date in activities {
            marks[calendar.startOfDay(for: date)] = .filled
        }
        return marks
    }

    func load(offset: Int, force: Bool = false) async {
        if !force, case .loaded = weeks[offset] { return }
        if force {
            await activityClient.invalidateActivities()
        }

        let start = weekStart(forOffset: offset)
        guard let end = calendar.date(byAdding: .day, value: 6, to: start),
              let nextWeek = calendar.date(byAdding: .day, value: 7, to: start)
        else { return }

        do {
            let token = try await tokenProvider()
            async let planned = client.plannedSessions(from: start, to: end, token: token)
            // The week's activities carry their own link back to the plan, so the merge
            // needs no extra endpoint. A failure here degrades to the prescription alone
            // rather than emptying the week.
            async let recorded = try? activityClient.activities(token: token)

            let entries = PlanEntryBuilder.entries(
                planned: try await planned,
                activities: (await recorded ?? []).filter { $0.date >= start && $0.date < nextWeek },
                calendar: calendar
            )
            withAnimation(SharpitMotion.reveal) {
                weeks[offset] = .loaded(entries)
            }
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .unauthorized {
            weeks[offset] = .unauthorized
        } catch {
            weeks[offset] = .error(error.localizedDescription)
        }
    }
}
