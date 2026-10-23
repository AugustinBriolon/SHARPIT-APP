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

                Section(eyebrow: String(localized: "Quantité")) {
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
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    energyPlate
                    macrosCard
                    problemNote
                }
                .padding(SharpitSpacing.pageInset)
                .animation(SharpitMotion.reveal, value: mode)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SharpitCanvasBackground())
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    /// The energy, big, on the ink plate: typed, or stepped by 50.
    private var energyPlate: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("Énergie par jour")
                .font(SharpitTypography.cardTitle)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                SharpitStepButton(symbol: "minus", label: String(localized: "Moins 50 kcal")) { stepKcal(-50) }
                VStack(spacing: 2) {
                    TextField("—", text: $kcal)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(SharpitColor.inkSurfaceForeground)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel("Calories")
                    Text("kcal")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.inkAccent)
                }
                .frame(maxWidth: .infinity)
                SharpitStepButton(symbol: "plus", label: String(localized: "Plus 50 kcal")) { stepKcal(50) }
            }
            Text(energyFooter)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
    }

    private func stepKcal(_ delta: Int) {
        let next = (NutritionTargetsInput.requiredKcal(kcal) ?? 2_000) + delta
        kcal = String(min(max(next, 800), 8_000))
    }

    private var energyFooter: String {
        let range = String(localized: "Entre 800 et 8 000 kcal par jour. Ta dépense d'entraînement s'y ajoute chaque jour.")
        return mode == .percent ? String(localized: "Obligatoire pour répartir en %. \(range)") : range
    }

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitFieldLabel(String(localized: "Macronutriments"))
            SharpitSegmentedChoice(
                options: [NutritionTargetsMode.grams, .percent],
                label: { $0 == .grams ? String(localized: "Grammes") : "%" },
                selection: Binding(get: { mode }, set: { if let next = $0 { mode = next } })
            )
            switch mode {
            case .grams:
                SharpitFormField(String(localized: "Protéines (g)"), placeholder: "—", text: $protein, keyboard: .decimalPad)
                SharpitFormField(String(localized: "Glucides (g)"), placeholder: "—", text: $carbs, keyboard: .decimalPad)
                SharpitFormField(String(localized: "Lipides (g)"), placeholder: "—", text: $fat, keyboard: .decimalPad)
                Text("Optionnels. Un champ vide retire l'objectif.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            case .percent:
                NutritionShareRow(title: String(localized: "Protéines"), grams: split.proteinG, text: $proteinPct)
                NutritionShareRow(title: String(localized: "Glucides"), grams: split.carbsG, text: $carbsPct)
                NutritionShareRow(title: String(localized: "Lipides"), grams: split.fatG, text: $fatPct)
                totalRow
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private var totalRow: some View {
        let split = split
        return HStack {
            Text("Total")
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: SharpitSpacing.xs)
            Text("\(split.total) %")
                .font(SharpitTypography.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(split.isBalanced ? SharpitColor.foreground : SharpitColor.signalRisk)
                .contentTransition(.numericText(value: Double(split.total)))
        }
        .animation(SharpitMotion.selection, value: split.total)
        .accessibilityElement(children: .combine)
        .accessibilityValue(split.isBalanced ? "\(split.total) %" : String(localized: "\(split.total) %, il faut 100 %"))
    }

    @ViewBuilder
    private var problemNote: some View {
        if let problem = mode == .percent ? percentProblem(split) : (gramsTargets == nil ? gramsProblem : nil) {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.signalRisk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gramsProblem: String {
        String(localized: "Une valeur sort des bornes : 800 à 8 000 kcal, au plus 600 g de protéines, 1 500 g de glucides, 500 g de lipides.")
    }

    private func percentProblem(_ split: NutritionTargetSplit) -> String? {
        if split.hasInvalidShare { return String(localized: "Chaque part est un nombre entier entre 0 et 100.") }
        if split.kcal == nil { return String(localized: "Entre ton énergie, entre 800 et 8 000 kcal, pour répartir tes macros.") }
        if !split.isBalanced { return String(localized: "Les trois parts doivent faire 100 % (\(split.total) % pour l'instant).") }
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
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                SharpitFieldLabel(title)
                Spacer(minLength: SharpitSpacing.xs)
                Text(grams.map { "≈ \(FoodPortion.gramsLabel(Double($0)))" } ?? "— g")
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .contentTransition(.numericText(value: Double(grams ?? 0)))
            }
            HStack(spacing: SharpitSpacing.xxs) {
                TextField("—", text: $text)
                    .keyboardType(.numberPad)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityLabel("\(title) en pourcentage")
                Text("%").foregroundStyle(SharpitColor.mutedForeground)
            }
            .sharpitFieldWell()
        }
        .animation(SharpitMotion.selection, value: grams)
    }
}
