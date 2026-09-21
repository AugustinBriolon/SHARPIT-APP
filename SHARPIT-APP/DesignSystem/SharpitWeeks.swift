import Foundation

/// Weeks addressed by their offset from the current one — Monday first, French calendar.
///
/// An offset is a stable identity for a page in a pager: page 3 is always three weeks
/// ahead. The range is bounded so a pager holds a fixed set of pages instead of an
/// infinite one, which is where paging bugs live.
struct SharpitWeeks: Sendable {
    let offsets: ClosedRange<Int>
    let calendar: Calendar
    private let now: @Sendable () -> Date

    init(offsets: ClosedRange<Int>, now: @escaping @Sendable () -> Date = { Date() }) {
        self.offsets = offsets
        self.now = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = SharpitLocale.french
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    private var currentWeekStart: Date {
        let today = now()
        return calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
    }

    func weekStart(forOffset offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset * 7, to: currentWeekStart) ?? currentWeekStart
    }

    func weekDays(forOffset offset: Int) -> [Date] {
        let start = weekStart(forOffset: offset)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The offset of the week containing `day`, clamped to the range.
    func offset(forWeekContaining day: Date) -> Int {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        let days = calendar.dateComponents([.day], from: currentWeekStart, to: start).day ?? 0
        // Rounded, not truncated: a daylight-saving change makes a week 167 or 169 hours.
        let weeks = Int((Double(days) / 7).rounded())
        return min(max(weeks, offsets.lowerBound), offsets.upperBound)
    }

    /// Every day the range covers.
    var selectableDates: ClosedRange<Date> {
        let first = weekStart(forOffset: offsets.lowerBound)
        let last = weekDays(forOffset: offsets.upperBound).last ?? first
        return first...last
    }
}
