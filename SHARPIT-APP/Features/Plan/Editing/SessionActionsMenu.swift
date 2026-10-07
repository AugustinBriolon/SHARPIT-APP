import SwiftUI

/// The drawer's « … »: what the athlete can do to the session itself. Asking the coach,
/// linking and the watch stay in the drawer's body, where they were.
struct SessionActionsMenu: View {
    let session: V1PlannedSessionItem
    let onEdit: () -> Void
    let onMove: (Date) -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button(action: onEdit) {
                Label("Modifier", systemImage: "pencil")
            }
            Menu {
                ForEach(PlanMoveDays.days(for: session), id: \.self) { day in
                    Button(PlanMoveDays.label(day)) { onMove(day) }
                }
            } label: {
                Label("Déplacer", systemImage: "calendar")
            }
            Divider()
            // RootView's .tint(primary) otherwise paints the trash green while the
            // role paints the title red — force both through the destructive token.
            Button(role: .destructive, action: onDelete) {
                Label {
                    Text("Supprimer")
                } icon: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(SharpitColor.destructive)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(SharpitTypography.bodyEmphasis)
        }
        .accessibilityLabel("Actions de la séance")
    }
}

/// Where « Déplacer » offers to take a session: the seven days from today, its own day left
/// out. Further than that is a date to pick, in « Modifier ».
enum PlanMoveDays {
    static func days(for session: V1PlannedSessionItem, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .filter { !calendar.isDate($0, inSameDayAs: session.date) }
    }

    /// « Aujourd’hui », « Demain », then « Mercredi 8 octobre ».
    static func label(_ day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Aujourd’hui" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Demain"
        }
        let text = day.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide))
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
