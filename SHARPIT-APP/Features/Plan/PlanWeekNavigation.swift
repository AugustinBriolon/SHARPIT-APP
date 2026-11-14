import SwiftUI

/// A month, to jump to any week the pager holds. Each day says what it holds — an activity,
/// a session still to do, one missed — so a busy or an empty week shows before it is opened.
struct PlanCalendarSheet: View {
    let store: PlanStore

    @State private var marks: [Date: SharpitCalendarMark] = [:]

    var body: some View {
        SharpitCalendarSheet(
            title: String(localized: "Semaine"),
            initial: store.weekStart,
            weeks: store.weekCalendar,
            marks: marks,
            legend: [(.filled, String(localized: "Activité")), (.ring, String(localized: "Prévue")), (.muted, String(localized: "Manquée"))],
            onPick: { store.showWeek(containing: $0) },
            onToday: { store.goToToday() }
        )
        .task { marks = await store.calendarMarks() }
    }
}
