import SwiftUI

/// Résumé's nutrition card: today's calories against the goal and the three macros, opening
/// the day's food log, for every athlete. Without a food log it opens the sources.
struct NutritionTodayCard: View {
    let phase: NutritionTodayStore.Phase
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
                .sharpitCardSpecularBorder()
        }
        .buttonStyle(.sharpitPressable)
        .disabled(phase == .loading)
        .accessibilityHint(hint)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            header
            switch phase {
            case .loaded(let day):
                loaded(day)
            case .loading:
                loaded(Self.placeholder)
                    .redacted(reason: .placeholder)
            case .empty:
                note("Rien de noté aujourd'hui pour l'instant.")
            case .disconnected:
                note("Connecte MyFitnessPal pour suivre tes apports.")
            case .failed:
                note("Journal alimentaire indisponible pour l'instant.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Nutrition", systemImage: "fork.knife")
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(SharpitTypography.label)
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
                .accessibilityHidden(true)
        }
    }

    private func loaded(_ day: V1NutritionDay) -> some View {
        let calories = day.goals?.calories
        return VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text(NutritionReadout.kcal(day.calories))
                    .font(SharpitTypography.gaugeScore)
                    .tracking(SharpitTypography.gaugeScoreTracking)
                    .foregroundStyle(NutritionReadout.goalTone(pct: calories?.pct))
                    .contentTransition(.numericText())
                Text(calories?.goal.map { "/ \(NutritionReadout.kcal($0)) kcal" } ?? "kcal")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer(minLength: 0)
                if let remaining = NutritionReadout.remainingLabel(calories?.remaining) {
                    Text(remaining)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            if let calories, calories.goal != nil {
                NutritionGoalBar(
                    fill: NutritionReadout.fill(pct: calories.pct),
                    tone: NutritionReadout.goalTone(pct: calories.pct)
                )
                .frame(height: 6)
            }
            HStack(spacing: SharpitSpacing.md) {
                ForEach(NutritionReadout.Macro.allCases, id: \.self) { macro in
                    macroFigure(macro, day: day)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func macroFigure(_ macro: NutritionReadout.Macro, day: V1NutritionDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xxs) {
            Text(macro.short)
                .font(SharpitTypography.label)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(NutritionReadout.grams(macro.consumed(in: day)))
                .font(SharpitTypography.instrument)
                .foregroundStyle(SharpitColor.foreground)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(macro.label) \(NutritionReadout.grams(macro.consumed(in: day)))")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(SharpitTypography.body)
            .foregroundStyle(SharpitColor.mutedForeground)
            .multilineTextAlignment(.leading)
    }

    private var hint: String {
        switch phase {
        case .disconnected: "Ouvre les paramètres"
        default: "Ouvre le journal alimentaire du jour"
        }
    }

    /// The loaded card's shape while the day loads.
    private static let placeholder = V1NutritionDay(
        calories: 1_850, protein: 110, carbohydrates: 220, fat: 60, fiber: nil, sugar: nil,
        complete: false, goals: nil, fuelDensity: nil, meals: []
    )
}
