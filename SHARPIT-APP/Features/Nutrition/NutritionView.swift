import Charts
import SwiftUI

/// The day's food log (SharpIt Pro): what was eaten against the day's goals, the coach's
/// reading of it, the macros, every meal and its entries, then the week. The day picker is
/// the drill-downs' own, so any past day opens the same way as Sommeil's.
struct NutritionView: View {
    @State private var store: DayResourceStore<V1NutritionResponse>

    init(
        client: any NutritionServing,
        tokenProvider: @escaping () async throws -> String,
        day: Date = .now
    ) {
        _store = State(initialValue: DayResourceStore(
            failureMessage: "Ton journal alimentaire n'a pas pu être chargé.",
            tokenProvider: tokenProvider,
            day: day,
            fetch: { try await client.nutrition(trainingDayId: $0, token: $1) }
        ))
    }

    var body: some View {
        DayDetailScaffold(
            title: "Nutrition",
            emptySymbol: "fork.knife",
            unavailableTitle: "Nutrition indisponible",
            store: store
        ) { nutrition in
            NutritionSections(nutrition: nutrition)
        }
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct NutritionSections: View {
    let nutrition: V1NutritionResponse

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            if let day = nutrition.day {
                NutritionHero(day: day, diet: nutrition.diet)
                if let reading = nutrition.coachReading {
                    NutritionCoachCard(reading: reading)
                }
                NutritionMacrosSection(day: day)
                if !day.meals.isEmpty {
                    NutritionMealsSection(meals: day.meals, flagged: flaggedEntries)
                }
            }
            if nutrition.history.contains(where: { $0.calories != nil }) {
                NutritionWeekSection(history: nutrition.history)
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.bottom, SharpitSpacing.xl)
    }

    private var flaggedEntries: [String: String] {
        guard case .ready(let ready) = nutrition.coachReading else { return [:] }
        return Dictionary(
            ready.flaggedEntries.map { ("\($0.meal)|\($0.entry)", NutritionReadout.flagLabel($0.reason)) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

// MARK: - Intake against the day's goal

private struct NutritionHero: View {
    let day: V1NutritionDay
    let diet: [String]

    private var calories: V1NutritionMacro? { day.goals?.calories }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text(NutritionReadout.kcal(day.calories))
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                    .foregroundStyle(NutritionReadout.goalTone(pct: calories?.pct))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(calories?.goal.map { "/ \(NutritionReadout.kcal($0)) kcal" } ?? "kcal")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize()
                Spacer(minLength: 0)
            }

            if let calories {
                NutritionGoalBar(fill: NutritionReadout.fill(pct: calories.pct), tone: NutritionReadout.goalTone(pct: calories.pct))
                    .frame(height: 8)
            }

            if let goals = day.goals {
                HStack(spacing: SharpitSpacing.sm) {
                    SharpitStatTile(
                        caption: (goals.calories.remaining ?? 0) < 0 ? "Au-delà" : "Restant",
                        value: NutritionReadout.kcal(goals.calories.remaining.map(abs)),
                        unit: "kcal",
                        note: goals.calories.pct.map { "\(Int($0.rounded())) % de l'objectif" }
                    )
                    SharpitStatTile(
                        caption: "Exercice",
                        value: "+\(NutritionReadout.kcal(goals.exerciseCalories))",
                        unit: "kcal",
                        note: "Budget \(NutritionReadout.kcal(goals.calorieBudget)) kcal"
                    )
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(([day.complete ? "Journée close" : "Journée en cours"] + diet).joined(separator: " · "))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }
}

/// A goal as a filled track: the share of the goal eaten so far.
struct NutritionGoalBar: View {
    let fill: Double
    let tone: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SharpitColor.analysisGrid)
                Capsule()
                    .fill(tone)
                    .frame(width: max(geo.size.width * fill, fill > 0 ? 6 : 0))
            }
        }
        .animation(SharpitMotion.reveal, value: fill)
        .accessibilityHidden(true)
    }
}

// MARK: - Coach reading

private struct NutritionCoachCard: View {
    @Environment(ShellRouter.self) private var router
    let reading: V1NutritionCoachReading

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                SharpitEyebrow("Lecture du coach")
                Spacer(minLength: 0)
                CoachDiscussButton(title: "Discuter") {
                    router.discussWithCoach(about: CoachDiscuss.describe(.today))
                }
            }
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                content
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch reading {
        case .ready(let ready):
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                if ready.isProvisional {
                    Text("Journée en cours")
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Text(ready.verdict.headline)
                    .font(SharpitTypography.verdict)
                    .tracking(SharpitTypography.verdictTracking)
                    .foregroundStyle(NutritionReadout.tone(for: ready.verdict.tone))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ready.findings, id: \.self) { finding in
                SharpitInsightRow(
                    title: NutritionReadout.jobLabel(finding.job),
                    detail: finding.text,
                    tone: NutritionReadout.tone(for: ready.verdict.tone)
                )
            }
            Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                Image(systemName: "arrow.turn.down.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityHidden(true)
                Text(ready.action.text)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .pending:
            statusLine("Le coach lit ta journée…", symbol: "ellipsis")
        case .awaitingDayEnd:
            statusLine("La lecture arrive une fois la journée avancée.", symbol: "clock")
        case .unavailable:
            statusLine("Lecture du coach indisponible pour ce jour.", symbol: "minus.circle")
        }
    }

    private func statusLine(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(SharpitTypography.body)
            .foregroundStyle(SharpitColor.mutedForeground)
    }
}

// MARK: - Macros

private struct NutritionMacrosSection: View {
    let day: V1NutritionDay

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Macronutriments")
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                ForEach(NutritionReadout.Macro.allCases, id: \.self) { macro in
                    MacroRow(
                        label: macro.label,
                        consumed: macro.consumed(in: day),
                        line: day.goals.map(macro.line(in:)),
                        perKg: perKg(macro)
                    )
                }
                if day.fiber != nil || day.sugar != nil {
                    Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
                    HStack {
                        fact("Fibres", NutritionReadout.grams(day.fiber))
                        Spacer(minLength: 0)
                        fact("Sucres", NutritionReadout.grams(day.sugar))
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
        }
    }

    private func perKg(_ macro: NutritionReadout.Macro) -> String? {
        guard let density = day.fuelDensity else { return nil }
        switch macro {
        case .protein: return NutritionReadout.perKg(density.proteinGPerKg)
        case .carbohydrates: return NutritionReadout.perKg(density.carbohydratesGPerKg)
        case .fat: return nil
        }
    }

    private func fact(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(value)
                .font(SharpitTypography.instrument)
                .foregroundStyle(SharpitColor.foreground)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MacroRow: View {
    let label: String
    let consumed: Double
    let line: V1NutritionMacro?
    let perKg: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                if let perKg {
                    Text(perKg)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer(minLength: 0)
                Text(NutritionReadout.grams(consumed))
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(NutritionReadout.goalTone(pct: line?.pct))
                if let goal = line?.goal {
                    Text("/ \(NutritionReadout.grams(goal))")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            if let line, line.goal != nil {
                NutritionGoalBar(fill: NutritionReadout.fill(pct: line.pct), tone: NutritionReadout.goalTone(pct: line.pct))
                    .frame(height: 5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Meals

private struct NutritionMealsSection: View {
    let meals: [V1NutritionMeal]
    /// Flag label by `meal|entry`, from the coach reading.
    let flagged: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Repas · \(meals.count)")
            VStack(spacing: SharpitSpacing.sm) {
                ForEach(meals, id: \.self) { meal in
                    MealCard(meal: meal, flagged: flagged)
                }
            }
        }
    }
}

private struct MealCard: View {
    let meal: V1NutritionMeal
    let flagged: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(meal.label)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 0)
                Text("\(NutritionReadout.kcal(meal.calories)) kcal")
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.foreground)
            }
            Text(macroLine(protein: meal.protein, carbs: meal.carbs, fat: meal.fat))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)

            if !meal.entries.isEmpty {
                Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    ForEach(meal.entries, id: \.self) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private func entryRow(_ entry: V1NutritionEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let flag = flagged["\(meal.name)|\(entry.name)"] ?? flagged["\(meal.label)|\(entry.name)"] {
                    Label(flag, systemImage: "exclamationmark.circle")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalCaution)
                }
            }
            Spacer(minLength: 0)
            Text(NutritionReadout.kcal(entry.calories))
                .font(SharpitTypography.meta)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .accessibilityElement(children: .combine)
    }

    private func macroLine(protein: Double, carbs: Double, fat: Double) -> String {
        "P \(NutritionReadout.grams(protein)) · G \(NutritionReadout.grams(carbs)) · L \(NutritionReadout.grams(fat))"
    }
}

// MARK: - The week

private struct NutritionWeekSection: View {
    let history: [V1NutritionHistoryDay]

    private var days: [(date: Date, calories: Double, goal: Double?)] {
        history.compactMap { day in
            guard let calories = day.calories, let date = TrainingDayId.date(day.date) else { return nil }
            return (date, calories, day.goalCalories)
        }
    }

    /// The whole week on the axis, so one logged day stays one day wide.
    private var weekDomain: ClosedRange<Date> {
        let dates = history.compactMap { TrainingDayId.date($0.date) }
        guard let first = dates.first, let last = dates.last,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: last)
        else { return Date.now...Date.now }
        return first...end
    }

    /// The goal most days carried, drawn once as the reference line.
    private var referenceGoal: Double? {
        history.compactMap(\.goalCalories).last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Semaine · \(history.count) jours")
            Chart {
                ForEach(days, id: \.date) { day in
                    BarMark(
                        x: .value("Jour", day.date, unit: .day),
                        y: .value("kcal", day.calories)
                    )
                    .foregroundStyle(tone(for: day))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                if let referenceGoal {
                    RuleMark(y: .value("Objectif", referenceGoal))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("objectif \(NutritionReadout.kcal(referenceGoal))")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                }
            }
            .chartXScale(domain: weekDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                    AxisValueLabel {
                        if let kcal = value.as(Double.self) { Text(NutritionReadout.kcal(kcal)) }
                    }
                }
            }
            .frame(height: 160)
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
        }
    }

    private func tone(for day: (date: Date, calories: Double, goal: Double?)) -> Color {
        guard let goal = day.goal, goal > 0 else { return SharpitColor.signalBase }
        return NutritionReadout.isOnGoal(pct: day.calories / goal * 100)
            ? SharpitColor.signalBase
            : SharpitColor.signalCaution
    }
}
