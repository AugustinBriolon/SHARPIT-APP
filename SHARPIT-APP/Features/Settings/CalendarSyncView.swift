import SwiftUI

/// Deprecated: calendar sync is managed in Sources › Priorités. Kept so older deep links still land usefully.
struct CalendarSyncView: View {
    let tokenProvider: () async throws -> String
    let appleCalendar: AppleCalendarSource

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SourcePrioritiesView(tokenProvider: tokenProvider, appleCalendar: appleCalendar)
                } label: {
                    Label {
                        Text("Priorités calendrier")
                            .font(SharpitTypography.bodyEmphasis)
                    } icon: {
                        SharpitRowIcon(symbol: "list.number")
                    }
                }
            } footer: {
                SharpitListFooter(
                    "Relie Calendrier Apple dans Sources, puis choisis la source principale et le calendrier d’écriture ici."
                )
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("Calendrier de l'iPhone")
        .navigationBarTitleDisplayMode(.inline)
    }
}
