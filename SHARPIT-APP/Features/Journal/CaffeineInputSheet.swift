import SwiftUI

/// Caffeine, on the journal's shared amount sheet: the usual drinks to add, ± 20 mg to tune.
struct CaffeineInputSheet: View {
    @Bindable var store: JournalStore

    static let amount = JournalAmountSheet.Amount(
        title: String(localized: "Caféine"),
        caption: String(localized: "Consommée sur la journée"),
        format: JournalAmountFormat.milligrams,
        stepDelta: 20,
        portions: [
            .init(id: "tea", label: String(localized: "Thé"), symbol: "cup.and.saucer", delta: 40),
            .init(id: "espresso", label: String(localized: "Expresso"), symbol: "cup.and.saucer.fill", delta: 60),
            .init(id: "energy", label: String(localized: "Énergie"), symbol: "bolt.fill", delta: 80),
            .init(id: "filter", label: String(localized: "Filtre"), symbol: "mug", delta: 100),
            .init(id: "double", label: String(localized: "Double expresso"), symbol: "mug.fill", delta: 120),
        ],
        portionLabel: { "+ \(JournalAmountFormat.milligrams($0.delta))" },
        resetTitle: String(localized: "Remettre à zéro"),
        hue: SharpitColor.pillarNutrition
    )

    var body: some View {
        JournalAmountSheet(
            amount: Self.amount,
            value: store.entry.caffeineMg ?? 0,
            onAdjust: { store.adjustCaffeine(by: $0) },
            onReset: { store.setCaffeine(0) }
        )
    }
}
