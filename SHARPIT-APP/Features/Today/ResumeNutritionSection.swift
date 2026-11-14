import SwiftUI

/// Résumé's nutrition, read on the sheet: the day's energy against its goal, then the three
/// macros as thin bars. The whole block opens the day's food log, where a meal is logged.
struct ResumeNutritionSection: View {
    let phase: NutritionTodayStore.Phase
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Nutrition")
                        .font(SharpitTypography.sectionTitle)
                        .tracking(SharpitTypography.sectionTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer(minLength: SharpitSpacing.xs)
                    Text(trailing)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SharpitColor.slate)
                        .accessibilityHidden(true)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .disabled(phase == .loading)
        .accessibilityElement(children: .combine)
        .accessibilityHint(phase == .empty ? String(localized: "Ouvre le journal pour noter un repas") : String(localized: "Ouvre le journal alimentaire du jour"))
    }

    /// « 3 repas », beside the title.
    private var trailing: String {
        if case .loaded(let day) = phase { return NutritionReadout.mealsCount(day.meals.count) }
        return ""
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loaded(let day):
            glance(day)
        case .loading:
            glance(NutritionReadout.placeholderDay).redacted(reason: .placeholder)
        case .empty:
            message(String(localized: "Rien de noté aujourd'hui. Scanne un emballage ou cherche un aliment."))
        case .failed:
            message(String(localized: "Journal indisponible. Touche pour réessayer."))
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
            .foregroundStyle(SharpitColor.slate)
            .multilineTextAlignment(.leading)
    }

    private func glance(_ day: V1NutritionDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            (Text(NutritionReadout.kcal(day.calories))
                .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                + Text(day.goals?.calories.goal.map { " / \(NutritionReadout.kcal($0)) kcal" } ?? " kcal")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate))
                .contentTransition(.numericText())
            HStack(alignment: .top, spacing: SharpitSpacing.md) {
                macro(String(localized: "Protéines"), day.protein, day.goals?.protein)
                macro(String(localized: "Glucides"), day.carbohydrates, day.goals?.carbohydrates)
                macro(String(localized: "Lipides"), day.fat, day.goals?.fat)
            }
        }
    }

    /// A macro: its name, the thin bar of what was eaten over its goal, and the grams.
    private func macro(_ name: String, _ eaten: Double, _ goal: V1NutritionMacro?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(1)
            SharpitBarTrack(fraction: NutritionReadout.fill(pct: goal?.pct), tone: SharpitColor.pillarNutrition)
                .frame(height: 4)
            (Text(NutritionReadout.grams(eaten))
                .foregroundStyle(SharpitColor.foreground)
                + Text(goal?.goal.map { " / \(NutritionReadout.grams($0))" } ?? "")
                .foregroundStyle(SharpitColor.slate))
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
