import EventKit
import SwiftUI

/// Chooses which iPhone calendar receives planned sessions when Calendrier Apple is primary.
struct AppleCalendarPickerView: View {
    private let sync: AppleCalendarSync
    private let onSelected: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var calendars: [WritableCalendarRow] = []
    @State private var refused = false

    init(
        sync: AppleCalendarSync = .shared,
        onSelected: @escaping () -> Void = {}
    ) {
        self.sync = sync
        self.onSelected = onSelected
    }

    var body: some View {
        Group {
            if refused {
                ContentUnavailableView {
                    Label("Accès Calendrier requis", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Autorise SharpIt dans Réglages › Confidentialité › Calendriers, puis reviens ici.")
                }
            } else if calendars.isEmpty {
                ContentUnavailableView {
                    Label("Aucun calendrier modifiable", systemImage: "calendar")
                } description: {
                    Text("Crée un calendrier dans l’app Calendrier ou autorise l’écriture sur un agenda existant.")
                }
            } else {
                calendarList
            }
        }
        .navigationTitle("Calendrier Apple")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var calendarList: some View {
        List {
            Section {
                ForEach(calendars) { row in
                    Button {
                        sync.writeCalendarIdentifier = row.id
                        onSelected()
                        dismiss()
                    } label: {
                        HStack(spacing: SharpitSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(SharpitTypography.bodyEmphasis)
                                    .foregroundStyle(SharpitColor.foreground)
                                if row.title == AppleCalendarSync.calendarTitle {
                                    Text("Calendrier SharpIt")
                                        .font(SharpitTypography.meta)
                                        .foregroundStyle(SharpitColor.mutedForeground)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if row.isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(SharpitColor.primary)
                                    .accessibilityLabel("Calendrier sélectionné")
                            }
                        }
                        .padding(.vertical, SharpitSpacing.xxs)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                SharpitListFooter(
                    "SHARPIT écrit tes séances planifiées dans ce calendrier quand Calendrier Apple est la source principale."
                )
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
    }

    private func load() async {
        guard await sync.requestAccess() else {
            refused = true
            return
        }
        let selected = sync.writeCalendarIdentifier
        calendars = sync.writableCalendars().map {
            WritableCalendarRow(id: $0.calendarIdentifier, title: $0.title, isSelected: $0.calendarIdentifier == selected)
        }
    }
}

private struct WritableCalendarRow: Identifiable {
    let id: String
    let title: String
    let isSelected: Bool
}
