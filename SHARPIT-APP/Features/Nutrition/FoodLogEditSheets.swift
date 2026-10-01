import SwiftUI

/// A logged food, edited: a new weight or another meal, or taken out. Saved on « OK » and shown
/// in the day at once (`FoodLogStore.update`).
struct FoodEntryEditSheet: View {
    let store: FoodLogStore
    let entry: V1FoodLogEntry

    @State private var gramsText: String
    @State private var meal: FoodLogMeal
    @FocusState private var isGramsFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: FoodLogStore, entry: V1FoodLogEntry) {
        self.store = store
        self.entry = entry
        _gramsText = State(initialValue: FoodPortion.editableFigure(entry.grams))
        _meal = State(initialValue: entry.meal)
    }

    private var grams: Double? { FoodLogForm.grams(gramsText) }

    private var change: FoodLogEntryChange? {
        guard let grams else { return nil }
        let change = FoodLogEntryChange(
            grams: grams == entry.grams ? nil : grams,
            meal: meal == entry.meal ? nil : meal
        )
        return change.grams == nil && change.meal == nil ? nil : change
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(SharpitTypography.cardTitle)
                            .tracking(SharpitTypography.cardTitleTracking)
                            .foregroundStyle(SharpitColor.foreground)
                        if let brand = entry.brand, !brand.isEmpty {
                            Text(brand)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                    FoodPortionPreview(nutrients: FoodPortion.nutrients(of: entry, grams: grams ?? entry.grams))
                }
                .sharpitListRows()

                Section(eyebrow: "Quantité") {
                    FoodGramsRows(text: $gramsText, isFocused: $isGramsFocused)
                    if grams == nil {
                        Text("Entre une quantité entre 1 et 5 000 g.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                }
                .sharpitListRows()

                Section {
                    FoodMealPicker(meal: $meal)
                }
                .sharpitListRows()

                Section {
                    Button("Supprimer l'aliment", role: .destructive) {
                        Task { await store.delete(entry) }
                        dismiss()
                    }
                }
                .sharpitListRows()
            }
            .sharpitGroupedList()
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { save() }
                        .disabled(grams == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func save() {
        if let change {
            Task { await store.update(entry, change) }
        }
        dismiss()
    }
}

/// The athlete's own daily targets: energy and the three macros. An empty field clears its
/// target. Saved on « OK »; the day's goals follow on the server.
struct NutritionTargetsSheet: View {
    let store: FoodLogStore

    @State private var kcal: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @Environment(\.dismiss) private var dismiss

    init(store: FoodLogStore) {
        self.store = store
        _kcal = State(initialValue: NutritionTargetsInput.text(store.targets.kcal.map(Double.init)))
        _protein = State(initialValue: NutritionTargetsInput.text(store.targets.proteinG))
        _carbs = State(initialValue: NutritionTargetsInput.text(store.targets.carbsG))
        _fat = State(initialValue: NutritionTargetsInput.text(store.targets.fatG))
    }

    private var parsed: V1NutritionTargets? {
        NutritionTargetsInput.parse(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(
                    eyebrow: "Énergie",
                    footer: "Entre 800 et 8 000 kcal par jour. Ta dépense d'entraînement s'y ajoute chaque jour."
                ) {
                    FoodNumberRow(title: "Calories", unit: "kcal", placeholder: "—", text: $kcal)
                }
                .sharpitListRows()

                Section(eyebrow: "Macronutriments", footer: "Optionnels. Un champ vide retire l'objectif.") {
                    FoodNumberRow(title: "Protéines", unit: "g", placeholder: "—", text: $protein)
                    FoodNumberRow(title: "Glucides", unit: "g", placeholder: "—", text: $carbs)
                    FoodNumberRow(title: "Lipides", unit: "g", placeholder: "—", text: $fat)
                }
                .sharpitListRows()

                if parsed == nil {
                    Section {
                        Text("Une valeur sort des bornes : 800 à 8 000 kcal, au plus 600 g de protéines, 1 500 g de glucides, 500 g de lipides.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                    .sharpitListRows()
                }
            }
            .sharpitGroupedList()
            .navigationTitle("Objectifs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { save() }
                        .disabled(parsed == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    private func save() {
        guard let parsed else { return }
        if parsed != store.targets {
            Task { await store.setTargets(parsed) }
        }
        dismiss()
    }
}
