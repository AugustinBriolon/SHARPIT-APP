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

    var selectedOffset = 0
    /// A day the strip asked the list to scroll to. Consumed by the visible page.
    var scrollTarget: Date?

    private var weeks: [Int: Phase] = [:]

    private let client: any PlannedSessionServing
    private let activityClient: any ActivityServing
    private let tokenProvider: () async throws -> String
    private let calendar: Calendar

    init(
        client: any PlannedSessionServing,
        activityClient: any ActivityServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.client = client
        self.activityClient = activityClient
        self.tokenProvider = tokenProvider
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = SharpitLocale.french
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    // MARK: - Weeks

    private var currentWeekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
    }

    func weekStart(forOffset offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset * 7, to: currentWeekStart) ?? currentWeekStart
    }

    /// The offset of the week containing `day`, clamped to the pager's range.
    func offset(forWeekContaining day: Date) -> Int {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        let days = calendar.dateComponents([.day], from: currentWeekStart, to: start).day ?? 0
        // Rounded, not truncated: a daylight-saving change makes a week 167 or 169 hours.
        let weeks = Int((Double(days) / 7).rounded())
        return min(max(weeks, Self.offsets.lowerBound), Self.offsets.upperBound)
    }

    var weekStart: Date { weekStart(forOffset: selectedOffset) }

    func weekDays(forOffset offset: Int) -> [Date] {
        let start = weekStart(forOffset: offset)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var weekDays: [Date] { weekDays(forOffset: selectedOffset) }

    var isCurrentWeek: Bool { selectedOffset == 0 }

    /// The range the calendar sheet may pick from — the pager's own bounds.
    var selectableDates: ClosedRange<Date> {
        let first = weekStart(forOffset: Self.offsets.lowerBound)
        let last = weekDays(forOffset: Self.offsets.upperBound).last ?? first
        return first...last
    }

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

    /// What the strip shows for `day` in the selected week, if that week has loaded.
    func status(on day: Date) -> PlanDayStatus? {
        guard case .loaded(let entries) = phase else { return nil }
        return PlanDayStatus.status(of: self.entries(on: day, from: entries))
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
        await load(offset: selectedOffset, force: true)
    }

    func load(offset: Int, force: Bool = false) async {
        if !force, case .loaded = weeks[offset] { return }

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
