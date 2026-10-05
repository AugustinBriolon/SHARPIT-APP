import SwiftUI

/// The rows the food log's forms share — a portion's figures, the grams with their presets, the
/// meal — so the portion picker and the entry editor read alike.

/// What a portion brings: the energy, then the three macros in their hues.
struct FoodPortionPreview: View {
    let nutrients: FoodPortion.Nutrients

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            figures
            NutritionMacroSplitBar(protein: nutrients.protein, carbohydrates: nutrients.carbs, fat: nutrients.fat, height: 6)
        }
        .animation(SharpitMotion.selection, value: nutrients)
    }

    private var figures: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xxs) {
                Text(NutritionReadout.kcal(nutrients.kcal))
                    .font(SharpitTypography.data)
                    .tracking(SharpitTypography.dataTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText(value: nutrients.kcal))
                Text("kcal")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: SharpitSpacing.xs)
            macro(.protein, nutrients.protein)
            macro(.carbohydrates, nutrients.carbs)
            macro(.fat, nutrients.fat)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(NutritionReadout.kcal(nutrients.kcal)) kilocalories, protéines \(FoodPortion.figure(nutrients.protein)) g, "
                + "glucides \(FoodPortion.figure(nutrients.carbs)) g, lipides \(FoodPortion.figure(nutrients.fat)) g"
        )
    }

    private func macro(_ macro: NutritionReadout.Macro, _ grams: Double) -> some View {
        VStack(spacing: 2) {
            Circle().fill(macro.tone).frame(width: 6, height: 6)
            Text(FoodPortion.figure(grams))
                .font(SharpitTypography.instrument)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.foreground)
            Text(macro.short)
                .font(SharpitTypography.label)
                .foregroundStyle(macro.tone)
        }
    }
}

/// The weight eaten, typed or picked from a few presets.
struct FoodGramsRows: View {
    @Binding var text: String
    var presets: [FoodPortion.Preset] = []
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            TextField("100", text: $text)
                .keyboardType(.decimalPad)
                .font(SharpitTypography.data)
                .focused(isFocused)
                .accessibilityLabel("Quantité en grammes")
            Text("g")
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        if !presets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SharpitSpacing.xs) {
                    ForEach(presets) { preset in
                        Button {
                            text = FoodPortion.editableFigure(preset.grams)
                        } label: {
                            Text(preset.label)
                                .font(SharpitTypography.meta.weight(.medium))
                                .foregroundStyle(isSelected(preset) ? SharpitColor.primaryForeground : SharpitColor.foreground)
                                .padding(.horizontal, SharpitSpacing.sm)
                                .frame(minHeight: 32)
                                .background(
                                    isSelected(preset) ? SharpitColor.primary : SharpitColor.analysisSurfaceAlt,
                                    in: Capsule()
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected(preset) ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowSeparator(.hidden, edges: .top)
        }
    }

    private func isSelected(_ preset: FoodPortion.Preset) -> Bool {
        FoodLogForm.grams(text) == preset.grams
    }
}

/// Which meal of the day the food goes in.
struct FoodMealPicker: View {
    @Binding var meal: FoodLogMeal

    var body: some View {
        Picker("Repas", selection: $meal) {
            ForEach(FoodLogMeal.allCases) { meal in
                Label(meal.label, systemImage: NutritionReadout.mealSymbol(meal.storedName)).tag(meal)
            }
        }
        .pickerStyle(.menu)
        .tint(SharpitColor.primary)
    }
}

/// Open Food Facts (ODbL) and Ciqual (Licence Ouverte) ask for their attribution wherever their
/// foods are listed or picked: one footer naming each source present.
struct FoodSourcesAttribution: View {
    let products: [V1FoodProduct]

    var body: some View {
        if let text = V1FoodProduct.attribution(for: products) {
            SharpitListFooter(text)
        }
    }
}

/// Reading a form's numbers the French way, within what the server accepts.
nonisolated enum FoodLogForm {
    static let maximumGrams = 5000.0

    /// A portion's weight: above zero, at most five kilograms.
    static func grams(_ text: String) -> Double? {
        guard let value = ProfileFieldFormat.parseDecimal(text), value <= maximumGrams else { return nil }
        return value
    }

    /// A figure that may be zero (a macro, kilocalories), within `range`; nil when invalid.
    static func amount(_ text: String, in range: ClosedRange<Double>) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), range.contains(value) else { return nil }
        return value
    }

    /// An optional figure: empty is fine (nil inside), anything typed must be valid.
    static func optionalAmount(_ text: String, in range: ClosedRange<Double>) -> Double?? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? .some(nil) : amount(text, in: range).map { .some($0) }
    }
}
