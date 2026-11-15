import SwiftUI

/// Picks the day a drill-down reads: the day in the middle of the bar, opening the month. Nights
/// and readiness exist only for days that have happened, so future days cannot be picked; in the
/// month a mark says whether a day holds data. A swipe on the page turns the day.
struct DayDetailDatePicker: View {
    let selectedDay: Date
    var hasData: (Date) -> Bool? = { _ in nil }
    /// Asks for the marks of a week about to be seen — the strip scrolled back, a month opened.
    var onShowWeek: (Date) -> Void = { _ in }
    let onSelect: (Date) -> Void

    /// How the capsule names the day: « Ven. 14 nov. », or « Nuit du 13 nov. » for a night.
    var label: @MainActor (Date) -> String = { DayDetailDatePicker.shortDay($0) }

    private let weeks = SharpitWeeks(offsets: SharpitWeeks.history)
    @State private var showingCalendar = false

    var body: some View {
        Button { showingCalendar = true } label: {
            HStack(spacing: 5) {
                Text(label(selectedDay))
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout, digits: true))
                    .lineLimit(1)
                    // The date changes in place: no roll, the page's slide says the direction.
                    .contentTransition(.identity)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(SharpitColor.foreground)
        }
        .accessibilityHint("Ouvre le calendrier")
        .sheet(isPresented: $showingCalendar) {
            SharpitCalendarSheet(
                title: String(localized: "Jour"),
                initial: selectedDay,
                weeks: weeks,
                range: weeks.selectableDates.lowerBound...Date.now,
                marks: calendarMarks,
                legend: [(.filled, String(localized: "Données")), (.muted, String(localized: "Aucune donnée"))],
                onPick: pick,
                onToday: { pick(.now) }
            )
        }
        // The calendar opens on a month: its marks are asked for as it shows.
        .onChange(of: showingCalendar) { _, shown in if shown { onShowWeek(selectedDay) } }
    }

    /// The strip's marks, for every day the calendar can show — only days already read say
    /// anything, as under the strip.
    private var calendarMarks: [Date: SharpitCalendarMark] {
        SharpitCalendarMark.dataMarks(in: weeks, hasData: hasData)
    }

    private func pick(_ day: Date) {
        onSelect(day)
    }

    /// « Ven. 14 nov. »
    static func shortDay(_ day: Date) -> String {
        day.sharpitFormatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).capitalizedFirst
    }
}
