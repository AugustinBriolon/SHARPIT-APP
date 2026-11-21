import SwiftUI

/// The day's time behind the wheel, on the journal's shared amount sheet: usual lengths to add,
/// a quarter hour to tune. Long sitting, often tense — the journal keeps it beside the rest.
struct DrivingInputSheet: View {
    @Bindable var store: JournalStore

    static let amount = JournalAmount(
        title: String(localized: "Conduite"),
        caption: String(localized: "Temps passé à conduire aujourd'hui"),
        format: { $0 == 0 ? "0 min" : JournalDrivingFormat.minutes($0) },
        stepDelta: 15,
        portions: [
            .init(id: "15", label: String(localized: "Un trajet court"), symbol: "car", delta: 15),
            .init(id: "30", label: String(localized: "Un trajet"), symbol: "car.fill", delta: 30),
            .init(id: "60", label: String(localized: "Une heure"), symbol: "road.lanes", delta: 60),
            .init(id: "120", label: String(localized: "Un long trajet"), symbol: "road.lanes.curved.right", delta: 120),
        ],
        portionLabel: { "+ \(JournalDrivingFormat.minutes($0.delta))" },
        resetTitle: String(localized: "Pas de conduite"),
        hue: SharpitColor.pillarCoach
    )

    var body: some View {
        JournalAmountSheet(
            amount: Self.amount,
            value: store.entry.drivingMinutes ?? 0,
            onAdjust: { store.adjustDriving(by: $0) },
            onReset: { store.setDriving(0) }
        )
    }
}
