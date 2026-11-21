import SwiftUI

/// Caffeine, on the journal's shared amount sheet: the usual drinks to add, ± 20 mg to tune, and
/// when the last one was had — now by default, changed for a coffee noted late (SHARPIT ADR-138):
/// a coffee at 10:00 and one at 16:00 do not weigh the same on the night.
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
        ) {
            if (store.entry.caffeineMg ?? 0) > 0 {
                CaffeineTimeRow(store: store)
            }
        }
    }
}

/// « Dernier café » and its time, a hairline above it. Without a time yet (a coffee added to
/// another day), a button gives it one.
private struct CaffeineTimeRow: View {
    @Bindable var store: JournalStore

    private var date: Binding<Date> {
        Binding(
            get: {
                let start = Calendar.current.startOfDay(for: .now)
                let minute = store.entry.caffeineMinute ?? 12 * 60
                return Calendar.current.date(byAdding: .minute, value: minute, to: start) ?? start
            },
            set: { store.setCaffeineMinute(FoodEatenTime.minuteOfDay($0)) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            HStack {
                Text("Dernier café")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 8)
                if store.entry.caffeineMinute == nil {
                    Button("Indiquer l'heure") { store.setCaffeineMinute(12 * 60) }
                        .buttonStyle(CliniqueButtonStyle(kind: .plain))
                } else {
                    DatePicker("Dernier café", selection: date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(SharpitColor.primary)
                }
            }
            .frame(minHeight: 44)
            .padding(.top, 8)
        }
    }
}
