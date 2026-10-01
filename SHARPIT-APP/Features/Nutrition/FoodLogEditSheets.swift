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

/// The athlete's own daily targets: energy and the three macros, in grams or as shares of the
/// energy (« % », which needs the energy and three shares totalling 100). An empty grams field
/// clears its target. Saved on « OK »; the day's goals follow on the server.
struct NutritionTargetsSheet: View {
    let store: FoodLogStore

    @State private var mode: NutritionTargetsMode
    @State private var kcal: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var proteinPct: String
    @State private var carbsPct: String
    @State private var fatPct: String
    @Environment(\.dismiss) private var dismiss

    init(store: FoodLogStore) {
        self.store = store
        let targets = store.targets
        let split = NutritionTargetSplit.prefill(from: targets)
        _mode = State(initialValue: targets.mode)
        _kcal = State(initialValue: NutritionTargetsInput.text(targets.kcal.map(Double.init)))
        _protein = State(initialValue: NutritionTargetsInput.text(targets.proteinG))
        _carbs = State(initialValue: NutritionTargetsInput.text(targets.carbsG))
        _fat = State(initialValue: NutritionTargetsInput.text(targets.fatG))
        _proteinPct = State(initialValue: split.proteinPct.map(String.init) ?? "")
        _carbsPct = State(initialValue: split.carbsPct.map(String.init) ?? "")
        _fatPct = State(initialValue: split.fatPct.map(String.init) ?? "")
    }

    private var gramsTargets: V1NutritionTargets? {
        NutritionTargetsInput.parse(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }

    private var split: NutritionTargetSplit {
        NutritionTargetSplit(kcal: kcal, protein: proteinPct, carbs: carbsPct, fat: fatPct)
    }

    private var parsed: V1NutritionTargets? {
        mode == .grams ? gramsTargets : split.targets
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Saisie des macros", selection: $mode) {
                        Text("Grammes").tag(NutritionTargetsMode.grams)
                        Text("%").tag(NutritionTargetsMode.percent)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section(eyebrow: "Énergie", footer: energyFooter) {
                    FoodNumberRow(title: "Calories", unit: "kcal", placeholder: "—", text: $kcal)
                }
                .sharpitListRows()

                switch mode {
                case .grams: gramsSections
                case .percent: percentSections
                }
            }
            .sharpitGroupedList()
            .navigationTitle("Objectifs")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: mode) { _, newMode in carryOver(to: newMode) }
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

    private var energyFooter: String {
        let range = "Entre 800 et 8 000 kcal par jour. Ta dépense d'entraînement s'y ajoute chaque jour."
        return mode == .percent ? "Obligatoire pour répartir en %. \(range)" : range
    }

    @ViewBuilder
    private var gramsSections: some View {
        Section(eyebrow: "Macronutriments", footer: "Optionnels. Un champ vide retire l'objectif.") {
            FoodNumberRow(title: "Protéines", unit: "g", placeholder: "—", text: $protein)
            FoodNumberRow(title: "Glucides", unit: "g", placeholder: "—", text: $carbs)
            FoodNumberRow(title: "Lipides", unit: "g", placeholder: "—", text: $fat)
        }
        .sharpitListRows()

        if gramsTargets == nil {
            Section {
                Text("Une valeur sort des bornes : 800 à 8 000 kcal, au plus 600 g de protéines, 1 500 g de glucides, 500 g de lipides.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
            }
            .sharpitListRows()
        }
    }

    @ViewBuilder
    private var percentSections: some View {
        let split = split
        Section(eyebrow: "Répartition", footer: "Des nombres entiers. Les grammes suivent ton énergie.") {
            NutritionShareRow(title: "Protéines", grams: split.proteinG, text: $proteinPct)
            NutritionShareRow(title: "Glucides", grams: split.carbsG, text: $carbsPct)
            NutritionShareRow(title: "Lipides", grams: split.fatG, text: $fatPct)
            LabeledContent("Total") {
                Text("\(split.total) %")
                    .font(SharpitTypography.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(split.isBalanced ? SharpitColor.foreground : SharpitColor.signalRisk)
                    .contentTransition(.numericText(value: Double(split.total)))
            }
            .animation(SharpitMotion.selection, value: split.total)
            .accessibilityValue(split.isBalanced ? "\(split.total) %" : "\(split.total) %, il faut 100 %")
        }
        .sharpitListRows()

        if let problem = percentProblem(split) {
            Section {
                Text(problem)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
            }
            .sharpitListRows()
        }
    }

    private func percentProblem(_ split: NutritionTargetSplit) -> String? {
        if split.hasInvalidShare { return "Chaque part est un nombre entier entre 0 et 100." }
        if split.kcal == nil { return "Entre ton énergie, entre 800 et 8 000 kcal, pour répartir tes macros." }
        if !split.isBalanced { return "Les trois parts doivent faire 100 % (\(split.total) % pour l'instant)." }
        return nil
    }

    /// What one mode already says carries into the other, so switching never empties the form.
    private func carryOver(to newMode: NutritionTargetsMode) {
        switch newMode {
        case .percent:
            guard let shares = NutritionTargetSplit.fromGramsForm(kcal: kcal, protein: protein, carbs: carbs, fat: fat) else { return }
            proteinPct = shares.proteinPct.map(String.init) ?? ""
            carbsPct = shares.carbsPct.map(String.init) ?? ""
            fatPct = shares.fatPct.map(String.init) ?? ""
        case .grams:
            guard let targets = split.targets else { return }
            protein = NutritionTargetsInput.text(targets.proteinG)
            carbs = NutritionTargetsInput.text(targets.carbsG)
            fat = NutritionTargetsInput.text(targets.fatG)
        }
    }

    private func save() {
        guard let parsed else { return }
        if parsed != store.targets {
            Task { await store.setTargets(parsed) }
        }
        dismiss()
    }
}

/// One macro's share of the energy, typed as a whole number, with the grams it is worth.
private struct NutritionShareRow: View {
    let title: String
    let grams: Int?
    @Binding var text: String

    var body: some View {
        LabeledContent {
            HStack(spacing: SharpitSpacing.xxs) {
                TextField("—", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel("\(title) en pourcentage")
                Text("%")
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(grams.map { "≈ \(FoodPortion.gramsLabel(Double($0)))" } ?? "— g")
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .contentTransition(.numericText(value: Double(grams ?? 0)))
            }
            .animation(SharpitMotion.selection, value: grams)
        }
    }
}
