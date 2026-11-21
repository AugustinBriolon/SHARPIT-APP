import SwiftUI

/// Water and liquids, on the journal's shared amount sheet: the usual containers to add, ± 10 cl to tune.
struct HydrationInputSheet: View {
    @Bindable var store: JournalStore

    static let amount = JournalAmount(
        title: String(localized: "Hydratation"),
        caption: String(localized: "Eau et liquides sur la journée"),
        format: { JournalAmountFormat.volume($0) },
        stepDelta: 100,
        portions: [
            .init(id: "glass", label: String(localized: "Verre d'eau"), symbol: "drop", delta: 250),
            .init(id: "mug", label: String(localized: "Grande tasse"), symbol: "mug", delta: 350),
            .init(id: "small_bottle", label: String(localized: "Petite bouteille"), symbol: "waterbottle", delta: 500),
            .init(id: "flask", label: String(localized: "Gourde sport"), symbol: "waterbottle.fill", delta: 750),
            .init(id: "liter", label: String(localized: "Bouteille 1 L"), symbol: "drop.fill", delta: 1000),
        ],
        portionLabel: { "+ \(JournalAmountFormat.volume($0.delta))" },
        resetTitle: String(localized: "Remettre à zéro"),
        hue: SharpitColor.pillarSleep
    )

    var body: some View {
        JournalAmountSheet(
            amount: Self.amount,
            value: store.entry.hydrationMl ?? 0,
            onAdjust: { store.adjustHydration(by: $0) },
            onReset: { store.setHydration(0) }
        )
    }
}
