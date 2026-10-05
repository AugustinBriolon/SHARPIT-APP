import SwiftUI

/// Picks the day a drill-down reads: the day's name, a way back to today, and the Plan's
/// week strip. Nights and readiness exist only for days that have happened, so the strip
/// stops at the current week and future days cannot be picked. Under each day, a mark
/// says whether it holds data, so an empty day is visible before it is opened.
struct DayDetailDatePicker: View {
    let selectedDay: Date
    var hasData: (Date) -> Bool? = { _ in nil }
    /// Asks for the marks of a week about to be seen — the strip scrolled back, a month opened.
    var onShowWeek: (Date) -> Void = { _ in }
    /// Back to today, offered beside the date only while another day is open.
    var onToday: (() -> Void)?
    let onSelect: (Date) -> Void

    private let weeks = SharpitWeeks(offsets: SharpitWeeks.history)
    @State private var weekOffset: Int
    @State private var showingCalendar = false

    init(
        selectedDay: Date,
        hasData: @escaping (Date) -> Bool? = { _ in nil },
        onShowWeek: @escaping (Date) -> Void = { _ in },
        onToday: (() -> Void)? = nil,
        onSelect: @escaping (Date) -> Void
    ) {
        self.selectedDay = selectedDay
        self.hasData = hasData
        self.onShowWeek = onShowWeek
        self.onToday = onToday
        self.onSelect = onSelect
        _weekOffset = State(initialValue: weeks.offset(forWeekContaining: selectedDay))
    }

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                Button { showingCalendar = true } label: {
                    HStack(spacing: SharpitSpacing.xxs) {
                        Text(selectedDay.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                            .font(SharpitTypography.verdict)
                            .tracking(SharpitTypography.verdictTracking)
                            .foregroundStyle(SharpitColor.foreground)
                            .contentTransition(.opacity)
                        Image(systemName: "chevron.down")
                            .font(SharpitTypography.label)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre le calendrier")

                // Beside the date it moves, not in the bar: there it merged into one glass pill
                // with each screen's own actions.
                Spacer(minLength: 0)
                if let onToday, !Calendar.current.isDateInToday(selectedDay) {
                    SharpitTodayChip(action: onToday)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(SharpitMotion.selection, value: Calendar.current.isDateInToday(selectedDay))
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
                title: "Jour",
                initial: selectedDay,
                weeks: weeks,
                range: weeks.selectableDates.lowerBound...Date.now,
                marks: calendarMarks,
                legend: [(.filled, "Données"), (.muted, "Aucune donnée")],
                onPick: pick,
                onToday: { pick(.now) }
            )
        }
        .onChange(of: weekOffset) { _, offset in onShowWeek(weeks.weekStart(forOffset: offset)) }
        // The day can change from outside — the navigation bar's "Aujourd'hui" — and the
        // strip follows it to that day's week.
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
        let calendar = weeks.calendar
        let today = calendar.startOfDay(for: .now)
        var marks: [Date: SharpitCalendarMark] = [:]
        var day = calendar.startOfDay(for: weeks.selectableDates.lowerBound)
        while day <= today {
            switch hasData(day) {
            case true?: marks[day] = .filled
            case false?: marks[day] = .muted
            case nil: break
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return marks
    }

    private func accessibilityLabel(for day: Date, isFuture: Bool) -> String {
        let date = day.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide))
        switch isFuture ? nil : hasData(day) {
        case true?: return "\(date), données disponibles"
        case false?: return "\(date), aucune donnée"
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

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
