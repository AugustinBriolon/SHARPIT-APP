import SwiftUI

/// The week's title. Tapping it opens the calendar — the way to reach a week that is not
/// next door, which a swipe would take a dozen gestures to get to.
struct PlanWeekHeader: View {
    let store: PlanStore
    let onOpenCalendar: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Button(action: onOpenCalendar) {
                HStack(spacing: SharpitSpacing.xxs) {
                    Text(weekRange)
                        .font(SharpitTypography.verdict)
                        .tracking(SharpitTypography.verdictTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    Image(systemName: "chevron.down")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Semaine du \(weekRange)")
            .accessibilityHint("Ouvre le calendrier")

            // "Aujourd'hui" lives in the navigation bar now (`SharpitTodayButton`).
            Spacer(minLength: 0)
        }
    }

    private var weekRange: String {
        guard let end = store.weekDays.last else {
            return store.weekStart.sharpitFormatted(.dateTime.day().month(.wide))
        }
        let formatter = DateIntervalFormatter()
        formatter.locale = SharpitLocale.french
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: store.weekStart, to: end)
            .replacingOccurrences(of: " 2026", with: "")
    }
}

/// The weeks, one page of seven days at a time. Tapping a day inside the visible week
/// scrolls the list to it; today carries the ink circle.
///
/// It shares `selectedOffset` with the content pager, so dragging either moves both.
struct PlanWeekStrip: View {
    @Bindable var store: PlanStore

    var body: some View {
        SharpitWeekStrip(weekOffset: $store.selectedOffset, weeks: store.weekCalendar) { day in
            Button { store.scrollTarget = day } label: {
                SharpitStripDay(
                    day: day,
                    emphasis: Calendar.current.isDateInToday(day) ? .filled : .plain
                ) {
                    PlanStatusDot(status: store.status(on: day, offset: store.offset(forWeekContaining: day)))
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PlanStatusDot.accessibilityLabel(day: day, status: store.status(on: day, offset: store.offset(forWeekContaining: day))))
            .accessibilityHint("Fait défiler la liste jusqu'à ce jour")
            .accessibilityAddTraits(.isButton)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SharpitColor.analysisBorder)
                .frame(height: 1)
        }
    }
}

/// Three states, distinguished by shape as well as colour: a filled dot, a ring, and a
/// muted dot. Colour alone would not survive colour-blindness or a bright screen.
private struct PlanStatusDot: View {
    let status: PlanDayStatus?

    var body: some View {
        switch status {
        case .executed:
            Circle().fill(SharpitColor.primary)
        case .planned:
            Circle().strokeBorder(SharpitColor.primary, lineWidth: 1.25)
        case .missed:
            Circle().fill(SharpitColor.mutedForeground)
        case nil:
            Color.clear
        }
    }

    static func accessibilityLabel(day: Date, status: PlanDayStatus?) -> String {
        let date = day.sharpitFormatted(.dateTime.weekday(.wide).day())
        switch status {
        case .executed: return "\(date), séance réalisée"
        case .planned: return "\(date), séance prévue"
        case .missed: return "\(date), séance non réalisée"
        case nil: return "\(date), repos"
        }
    }
}

/// A month, to jump to any week the pager holds. Each day says what it holds — an activity,
/// a session still to do, one missed — so a busy or an empty week shows before it is opened.
struct PlanCalendarSheet: View {
    let store: PlanStore

    @State private var marks: [Date: SharpitCalendarMark] = [:]

    var body: some View {
        SharpitCalendarSheet(
            title: "Semaine",
            initial: store.weekStart,
            weeks: store.weekCalendar,
            marks: marks,
            legend: [(.filled, "Activité"), (.ring, "Prévue"), (.muted, "Manquée")],
            onPick: { store.showWeek(containing: $0) },
            onToday: { store.goToToday() }
        )
        .task { marks = await store.calendarMarks() }
    }
}
