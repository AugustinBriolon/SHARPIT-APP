import SwiftUI

/// Picks the day a drill-down reads: the day's name, a way back to today, and the Plan's
/// week strip. Nights and readiness exist only for days that have happened, so the strip
/// stops at the current week and future days cannot be picked.
struct DayDetailDatePicker: View {
    let selectedDay: Date
    let onSelect: (Date) -> Void

    private let weeks = SharpitWeeks(offsets: -26...0)
    @State private var weekOffset = 0
    @State private var showingCalendar = false

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

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

                Spacer(minLength: 0)

                if !isToday {
                    Button("Aujourd'hui") { pick(.now) }
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.primary)
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)

            SharpitWeekStrip(weekOffset: $weekOffset, weeks: weeks) { day in
                let isFuture = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: .now)
                Button { pick(day) } label: {
                    SharpitStripDay(day: day, emphasis: emphasis(for: day, isFuture: isFuture))
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
                .accessibilityLabel(day.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)))
                .accessibilityAddTraits(Calendar.current.isDate(day, inSameDayAs: selectedDay) ? [.isButton, .isSelected] : .isButton)
            }
        }
        .onAppear { weekOffset = weeks.offset(forWeekContaining: selectedDay) }
        .sheet(isPresented: $showingCalendar) {
            SharpitCalendarSheet(
                title: "Jour",
                initial: selectedDay,
                weeks: weeks,
                range: weeks.selectableDates.lowerBound...Date.now,
                onPick: pick,
                onToday: { pick(.now) }
            )
        }
    }

    private func emphasis(for day: Date, isFuture: Bool) -> SharpitStripDay<Color>.Emphasis {
        if isFuture { return .unavailable }
        if Calendar.current.isDate(day, inSameDayAs: selectedDay) { return .filled }
        if Calendar.current.isDateInToday(day) { return .accent }
        return .plain
    }

    private func pick(_ day: Date) {
        SharpitHaptics.play(.light)
        weekOffset = weeks.offset(forWeekContaining: day)
        onSelect(day)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
