import SwiftUI

/// One meal of the day: its energy and macros on top, then every food, heaviest first, with
/// what each brings and the coach's flag when it raised one.
struct NutritionMealView: View {
    let meal: V1NutritionMeal
    let flags: [NutritionEntryFlag]

    private var entries: [V1NutritionEntry] {
        meal.entries.sorted { $0.calories > $1.calories }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                summary
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    SharpitEyebrow(meal.entries.count == 1 ? "1 aliment" : "\(meal.entries.count) aliments")
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            entryRow(entry)
                            if index < entries.count - 1 {
                                Rectangle()
                                    .fill(SharpitColor.analysisGrid)
                                    .frame(height: 1)
                                    .padding(.leading, SharpitSpacing.md)
                            }
                        }
                    }
                    .sharpitSurface(.panel)
                    .sharpitCardSpecularBorder()
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.md)
            .padding(.bottom, SharpitSpacing.xl)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(meal.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.md) {
            ZStack {
                Circle().fill(SharpitColor.primary.opacity(0.12)).frame(width: 52, height: 52)
                Image(systemName: NutritionReadout.mealSymbol(meal.name))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(NutritionReadout.kcal(meal.calories))
                    .font(SharpitTypography.gaugeScore)
                    .tracking(SharpitTypography.gaugeScoreTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text("kcal")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            HStack(spacing: SharpitSpacing.md) {
                macro(.protein, meal.protein)
                macro(.carbohydrates, meal.carbs)
                macro(.fat, meal.fat)
            }
        }
        .padding(SharpitSpacing.md)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
    }

    private func macro(_ macro: NutritionReadout.Macro, _ grams: Double) -> some View {
        VStack(spacing: 2) {
            Circle().fill(macro.tone).frame(width: 6, height: 6)
            Text("\(Int(grams.rounded()))")
                .font(SharpitTypography.instrument)
                .foregroundStyle(SharpitColor.foreground)
            Text(macro.short)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(macro.label) \(NutritionReadout.grams(grams))")
    }

    private func entryRow(_ entry: V1NutritionEntry) -> some View {
        let flag = flags.first { $0.matches(meal: meal, entry: entry.name) }
        return HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text("P \(Int(entry.protein.rounded())) · G \(Int(entry.carbs.rounded())) · L \(Int(entry.fat.rounded())) g")
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.mutedForeground)
                if let flag {
                    Label(flag.label, systemImage: "exclamationmark.circle.fill")
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(SharpitColor.signalCaution)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SharpitColor.signalCaution.opacity(0.12), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Text(NutritionReadout.kcal(entry.calories))
                .font(SharpitTypography.instrument)
                .foregroundStyle(SharpitColor.foreground)
        }
        .padding(SharpitSpacing.md)
        .accessibilityElement(children: .combine)
    }
}
