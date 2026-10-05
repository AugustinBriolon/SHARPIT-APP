import SwiftUI

/// Paramètres › Calendrier de l'iPhone: the plan copied into a « SharpIt » calendar (SharpIt Pro).
struct CalendarSyncView: View {
    let tokenProvider: () async throws -> String

    @Environment(ProStore.self) private var pro: ProStore?
    @State private var isOn = PlanCalendarSync.shared.isEnabled
    @State private var refused = false

    var body: some View {
        List {
            if pro?.isPro == true {
                Section(
                    eyebrow: "Synchro",
                    footer: "Tes séances des trois prochaines semaines s'écrivent dans un calendrier « SharpIt », et suivent chaque changement du plan. Le désactiver retire ce calendrier."
                ) {
                    Toggle("Copier mon plan dans Calendrier", isOn: Binding(get: { isOn }, set: switchTo))
                        .tint(SharpitColor.primary)
                    if refused {
                        Text("Accès refusé : autorise SharpIt dans Réglages › Confidentialité › Calendriers.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                }
                .sharpitListRows()
            } else {
                Section {
                    SharpitProTeaser(
                        title: "Synchro calendrier",
                        message: "Tes séances planifiées s'écrivent toutes seules dans le calendrier de ton iPhone, et suivent chaque changement de ton plan."
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .sharpitGroupedList()
        .navigationTitle("Calendrier de l'iPhone")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func switchTo(_ on: Bool) {
        isOn = on
        refused = false
        Task {
            if on {
                guard await PlanCalendarSync.shared.enable() else {
                    isOn = false
                    refused = true
                    return
                }
                await PlanCalendarSync.shared.refresh(
                    isPro: pro?.isPro ?? false,
                    plan: PlannedSessionClient(),
                    tokenProvider: tokenProvider
                )
            } else {
                PlanCalendarSync.shared.disable()
            }
        }
    }
}
