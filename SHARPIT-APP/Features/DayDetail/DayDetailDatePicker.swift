import SwiftUI

/// Picks the day a drill-down reads: the day's name and the Plan's week strip. Nights and
/// readiness exist only for days that have happened, so the strip stops at the current week
/// and future days cannot be picked. Under each day, a mark says whether it holds data, so
/// an empty day is visible before it is opened. Back to today lives only in the calendar sheet.
struct DayDetailDatePicker: View {
    let selectedDay: Date
    var hasData: (Date) -> Bool? = { _ in nil }
    /// Asks for the marks of a week about to be seen — the strip scrolled back, a month opened.
    var onShowWeek: (Date) -> Void = { _ in }
    let onSelect: (Date) -> Void

    private let weeks = SharpitWeeks(offsets: SharpitWeeks.history)
    @State private var weekOffset: Int
    @State private var showingCalendar = false

    init(
        selectedDay: Date,
        hasData: @escaping (Date) -> Bool? = { _ in nil },
        onShowWeek: @escaping (Date) -> Void = { _ in },
        onSelect: @escaping (Date) -> Void
    ) {
        self.selectedDay = selectedDay
        self.hasData = hasData
        self.onShowWeek = onShowWeek
        self.onSelect = onSelect
        _weekOffset = State(initialValue: weeks.offset(forWeekContaining: selectedDay))
    }

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            Button { showingCalendar = true } label: {
                HStack(spacing: SharpitSpacing.xxs) {
                    Text(selectedDay.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                        .font(SharpitTypography.verdict)
                        .tracking(SharpitTypography.verdictTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        // The date changes in place: no roll, the page's slide says the direction.
                        .contentTransition(.identity)
                    Image(systemName: "chevron.down")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre le calendrier")
            .padding(.horizontal, SharpitSpacing.pageInset)

            SharpitWeekStrip(weekOffset: $weekOffset, weeks: weeks) { day in
                let isFuture = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: .now)
                Button { pick(day) } label: {
                    SharpitStripDay(day: day, emphasis: emphasis(for: day, isFuture: isFuture)) {
                        SharpitDataDayMark(hasData: isFuture ? nil : hasData(day))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
                .accessibilityLabel(accessibilityLabel(for: day, isFuture: isFuture))
                .accessibilityAddTraits(Calendar.current.isDate(day, inSameDayAs: selectedDay) ? [.isButton, .isSelected] : .isButton)
            }
        }
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
        .onChange(of: weekOffset) { _, offset in onShowWeek(weeks.weekStart(forOffset: offset)) }
        .onChange(of: selectedDay) { _, day in
            let target = weeks.offset(forWeekContaining: day)
            if weekOffset != target {
                SharpitMotion.run(SharpitMotion.selection) { weekOffset = target }
            }
        }
    }

    /// The strip's marks, for every day the calendar can show — only days already read say
    /// anything, as under the strip.
    private var calendarMarks: [Date: SharpitCalendarMark] {
        SharpitCalendarMark.dataMarks(in: weeks, hasData: hasData)
    }

    private func accessibilityLabel(for day: Date, isFuture: Bool) -> String {
        let date = day.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide))
        switch isFuture ? nil : hasData(day) {
        case true?: return String(localized: "\(date), données disponibles")
        case false?: return String(localized: "\(date), aucune donnée")
        case nil: return date
        }
    }

    private func emphasis(for day: Date, isFuture: Bool) -> SharpitStripDay<SharpitDataDayMark>.Emphasis {
        if isFuture { return .unavailable }
        if Calendar.current.isDate(day, inSameDayAs: selectedDay) { return .filled }
        if Calendar.current.isDateInToday(day) { return .accent }
        return .plain
    }

    private func pick(_ day: Date) {
        weekOffset = weeks.offset(forWeekContaining: day)
        onSelect(day)
    }
}
