import SwiftUI

/// Résumé's nutrition card, built like the overnight gauges above it: a tinted badge and a
/// label on top, the day's energy against its goal on the left, the three macros as columns
/// filling toward their goals on the right, and one line of context at the foot. It opens the
/// day's food log — where a missing food log is linked too.
struct NutritionTodayCard: View {
    let phase: NutritionTodayStore.Phase
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
            .sharpitCardSpecularBorder()
        }
        .buttonStyle(.sharpitPressable)
        .disabled(phase == .loading)
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(SharpitColor.primary.opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: "fork.knife")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            }
            Text("Nutrition")
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.foreground.opacity(0.85))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loaded(let day):
            NutritionDayGlance(day: day)
        case .loading:
            NutritionDayGlance(day: NutritionReadout.placeholderDay)
                .redacted(reason: .placeholder)
        case .empty:
            message("Rien de noté aujourd'hui", detail: "Tes repas apparaîtront ici dès qu'ils seront dans ton journal.")
        case .disconnected:
            message("Aucun journal alimentaire", detail: "Connecte MyFitnessPal pour suivre ce que tu manges.")
        case .failed:
            message("Journal indisponible", detail: "Touche pour réessayer.")
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            Text(title)
                .font(SharpitTypography.cardTitle)
                .tracking(SharpitTypography.cardTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            Text(detail)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.leading)
        }
    }

    private var hint: String {
        phase == .disconnected ? "Ouvre la connexion à MyFitnessPal" : "Ouvre le journal alimentaire du jour"
    }
}

/// Energy on the left, macros on the right, context underneath.
private struct NutritionDayGlance: View {
    let day: V1NutritionDay

    private var calories: V1NutritionMacro? { day.goals?.calories }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(alignment: .bottom, spacing: SharpitSpacing.md) {
                energy
                Spacer(minLength: SharpitSpacing.sm)
                NutritionMacroColumns(day: day, height: 56)
            }
            footCapsule
        }
    }

    private var energy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(NutritionReadout.kcal(day.calories))
                .font(SharpitTypography.gaugeScore)
                .tracking(SharpitTypography.gaugeScoreTracking)
                .foregroundStyle(SharpitColor.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(calories?.goal.map { "sur \(NutritionReadout.kcal($0)) kcal" } ?? "kcal")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SharpitColor.mutedForeground)
            if let calories, calories.goal != nil {
                NutritionGoalBar(
                    fill: NutritionReadout.fill(pct: calories.pct),
                    tone: NutritionReadout.goalTone(pct: calories.pct)
                )
                .frame(width: 128, height: 4)
                .padding(.top, SharpitSpacing.xs)
            }
        }
    }

    private var footCapsule: some View {
        HStack(spacing: 4) {
            Text(NutritionReadout.mealsCount(day.meals.count))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(SharpitColor.mutedForeground)
            Text("·")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))
            Text(NutritionReadout.remainingLabel(calories?.remaining) ?? (day.complete ? "Journée close" : "Journée en cours"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SharpitColor.foreground)
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(SharpitColor.secondary.opacity(0.55))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(SharpitColor.border.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

/// The three macros as columns filling toward their goals, read at a glance.
struct NutritionMacroColumns: View {
    let day: V1NutritionDay
    var height: CGFloat = 56

    var body: some View {
        HStack(alignment: .bottom, spacing: SharpitSpacing.sm) {
            ForEach(NutritionReadout.Macro.allCases, id: \.self) { macro in
                column(macro)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            NutritionReadout.Macro.allCases
                .map { "\($0.label) \(NutritionReadout.grams($0.consumed(in: day)))" }
                .joined(separator: ", ")
        )
    }

    private func column(_ macro: NutritionReadout.Macro) -> some View {
        let fill = day.goals.flatMap { macro.line(in: $0).pct }.map { NutritionReadout.fill(pct: $0) } ?? 0
        return VStack(spacing: 4) {
            Text("\(Int(macro.consumed(in: day).rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SharpitColor.foreground)
            ZStack(alignment: .bottom) {
                Capsule().fill(SharpitColor.analysisGrid)
                Capsule()
                    .fill(macro.tone)
                    .frame(height: max(height * fill, fill > 0 ? 4 : 0))
            }
            .frame(width: 10, height: height)
            Text(macro.short)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }
}
