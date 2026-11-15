import SwiftUI

/// The rows the food log's forms share — a portion's figures, the grams with their presets, the
/// meal — so the portion picker and the entry editor read alike.

/// What a portion, a meal or a recipe brings: its energy read big, the split of its macros on one
/// bar in their hues, then each macro's grams. `caption` says what the energy is a share of.
struct FoodPortionPreview: View {
    let nutrients: FoodPortion.Nutrients
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(NutritionReadout.kcal(nutrients.kcal))
                    .font(SharpitTypography.system(size: 46, weight: .semibold, relativeTo: .largeTitle, digits: true))
                    .tracking(-1.2)
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText(value: nutrients.kcal))
                Text(caption.map { "kcal · \($0)" } ?? "kcal")
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            NutritionMacroSplitBar(protein: nutrients.protein, carbohydrates: nutrients.carbs, fat: nutrients.fat, height: 10)
            HStack(spacing: SharpitSpacing.xs) {
                macro(.carbohydrates, nutrients.carbs)
                Spacer(minLength: 0)
                macro(.protein, nutrients.protein)
                Spacer(minLength: 0)
                macro(.fat, nutrients.fat)
            }
        }
        .animation(SharpitMotion.selection, value: nutrients)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "\(NutritionReadout.kcal(nutrients.kcal)) kilocalories, protéines \(FoodPortion.figure(nutrients.protein)) g, ")
                + String(localized: "glucides \(FoodPortion.figure(nutrients.carbs)) g, lipides \(FoodPortion.figure(nutrients.fat)) g")
        )
    }

    private func macro(_ macro: NutritionReadout.Macro, _ grams: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(macro.label)
                .foregroundStyle(SharpitColor.slate)
            Text("\(FoodPortion.figure(grams)) g")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.foreground)
        }
        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// The weight eaten, read big between a minus and a plus — typed in place too — over a few
/// presets, the one in force in ink.
struct FoodGramsRows: View {
    @Binding var text: String
    var presets: [FoodPortion.Preset] = []
    var isFocused: FocusState<Bool>.Binding

    /// One tap moves the portion by a spoonful.
    private static let step = 10.0

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            HStack(spacing: 18) {
                SharpitStepButton(symbol: "minus", label: String(localized: "Moins 10 grammes")) { move(by: -Self.step) }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("100", text: $text)
                        .keyboardType(.decimalPad)
                        .font(SharpitTypography.system(size: 56, weight: .semibold, relativeTo: .largeTitle, digits: true))
                        .tracking(-1.6)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                        .focused(isFocused)
                        .accessibilityLabel("Quantité en grammes")
                    Text("g")
                        .font(SharpitTypography.system(size: 20, weight: .regular, relativeTo: .title3))
                        .foregroundStyle(SharpitColor.slate)
                }
                SharpitStepButton(symbol: "plus", label: String(localized: "Plus 10 grammes")) { move(by: Self.step) }
            }
            if !presets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SharpitSpacing.xs) {
                        ForEach(presets) { preset in
                            Button {
                                text = FoodPortion.editableFigure(preset.grams)
                            } label: {
                                Text(preset.label)
                                    .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                                    .foregroundStyle(isSelected(preset) ? SharpitColor.primaryForeground : SharpitColor.foreground)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 34)
                                    .background(isSelected(preset) ? SharpitColor.primary : .clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(isSelected(preset) ? .clear : SharpitColor.outline, lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected(preset) ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SharpitSpacing.xs)
        .listRowSeparator(.hidden)
    }

    private func move(by delta: Double) {
        let next = min(max((FoodLogForm.grams(text) ?? 0) + delta, 1), FoodLogForm.maximumGrams)
        text = FoodPortion.editableFigure(next)
    }

    private func isSelected(_ preset: FoodPortion.Preset) -> Bool {
        FoodLogForm.grams(text) == preset.grams
    }
}

/// What a weight of a food brings, a line per nutrient, each macro marked in its hue.
struct FoodNutrientLines: View {
    let nutrients: FoodPortion.Nutrients
    var fiber: Double? = nil

    var body: some View {
        line(String(localized: "Énergie"), NutritionReadout.kcal(nutrients.kcal), "kcal", SharpitColor.pillarNutrition)
        line(NutritionReadout.Macro.carbohydrates.label, FoodPortion.figure(nutrients.carbs), "g", NutritionReadout.Macro.carbohydrates.tone)
        line(NutritionReadout.Macro.protein.label, FoodPortion.figure(nutrients.protein), "g", NutritionReadout.Macro.protein.tone)
        line(NutritionReadout.Macro.fat.label, FoodPortion.figure(nutrients.fat), "g", NutritionReadout.Macro.fat.tone)
        if let fiber {
            line(String(localized: "Fibres"), FoodPortion.figure(fiber), "g", nil)
        }
    }

    private func line(_ name: String, _ value: String, _ unit: String, _ hue: Color?) -> some View {
        HStack(spacing: 10) {
            if let hue {
                Capsule().fill(hue).frame(width: 4, height: 18).accessibilityHidden(true)
            }
            Text(name)
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: SharpitSpacing.xs)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .accessibilityElement(children: .combine)
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
