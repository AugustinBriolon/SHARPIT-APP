import SwiftUI

/// The drawer's « … »: everything the athlete can do to the session besides asking the coach,
/// who keeps his pill beside the title. Each group is there only where the screen offers it.
struct SessionActionsMenu: View {
    /// Edit, move and delete; nil where the plan cannot be changed (Résumé, a brick's leg).
    var editing: SessionMenuEditing?
    /// « Envoyer sur ma montre », titled by where the session stands on the watch.
    var watch: SessionMenuAction?
    var onLink: (() -> Void)?

    /// Nothing to offer: the drawer shows no « … » at all rather than an empty menu.
    var isEmpty: Bool { editing == nil && watch == nil && onLink == nil }

    var body: some View {
        Menu {
            if let watch {
                Button(action: watch.action) {
                    Label(watch.title, systemImage: watch.symbolName)
                }
            }
            if let onLink {
                Button(action: onLink) {
                    Label("Lier à une séance réalisée", systemImage: "link")
                }
            }
            if let editing {
                if watch != nil || onLink != nil { Divider() }
                Button(action: editing.onEdit) {
                    Label("Modifier", systemImage: "pencil")
                }
                Menu {
                    ForEach(PlanMoveDays.days(for: editing.session), id: \.self) { day in
                        Button(PlanMoveDays.label(day)) { editing.onMove(day) }
                    }
                } label: {
                    Label("Déplacer", systemImage: "calendar")
                }
                Divider()
                SharpitDeleteMenuButton(action: editing.onDelete)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(SharpitTypography.bodyEmphasis)
        }
        .accessibilityLabel("Actions de la séance")
    }
}

struct SessionMenuEditing {
    let session: V1PlannedSessionItem
    let onEdit: () -> Void
    let onMove: (Date) -> Void
    let onDelete: () -> Void
}

struct SessionMenuAction {
    let title: String
    let symbolName: String
    let action: () -> Void
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
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Aujourd’hui") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return String(localized: "Demain")
        }
        let text = day.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide))
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
