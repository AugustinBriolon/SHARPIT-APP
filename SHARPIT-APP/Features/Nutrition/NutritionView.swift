import Charts
import SwiftUI

/// The day's food log, open to every athlete. Read top to bottom like the other day screens:
/// the energy dial, the coach's reading on the ink plate, the macros and where the energy came
/// from, the meals — each opening its own page — and the week, where a bar opens its day.
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
            NutritionSections(nutrition: nutrition) { day in
                Task { await store.select(day) }
            }
        }
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct NutritionSections: View {
    let nutrition: V1NutritionResponse
    var onSelectDay: (Date) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            if let day = nutrition.day {
                NutritionEnergyPlate(day: day, diet: nutrition.diet)
                coachReading
                NutritionMacrosSection(day: day)
                if !day.meals.isEmpty {
                    NutritionMealsSection(meals: day.meals, flags: flags)
                }
            }
            if nutrition.history.contains(where: { $0.calories != nil }) {
                NutritionWeekSection(
                    history: nutrition.history,
                    selectedDayId: nutrition.trainingDayId,
                    onSelectDay: onSelectDay
                )
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.bottom, SharpitSpacing.xl)
    }

    @ViewBuilder
    private var coachReading: some View {
        switch nutrition.coachReading {
        case .proRequired?:
            SharpitProTeaser(
                title: "Lecture du coach",
                message: "Le coach lit ce que tu as mangé face à ton entraînement, et te donne une action concrète."
            )
        case let reading?:
            NutritionCoachPlate(reading: reading)
        case nil:
            EmptyView()
        }
    }

    /// The coach's flags by meal key and entry name.
    private var flags: [NutritionEntryFlag] {
        guard case .ready(let ready) = nutrition.coachReading else { return [] }
        return ready.flaggedEntries.map {
            NutritionEntryFlag(meal: $0.meal, entry: $0.entry, label: NutritionReadout.flagLabel($0.reason))
        }
    }
}

struct NutritionEntryFlag: Hashable {
    let meal: String
    let entry: String
    let label: String

    func matches(meal other: V1NutritionMeal, entry name: String) -> Bool {
        (meal == other.name || meal == other.label) && entry == name
    }
}

// MARK: - Energy

/// The day's energy on the app's own dial, and the three numbers behind it.
private struct NutritionEnergyPlate: View {
    let day: V1NutritionDay
    let diet: [String]

    private var calories: V1NutritionMacro? { day.goals?.calories }

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            dial
            if let goals = day.goals {
                HStack(spacing: 0) {
                    figure("Objectif", NutritionReadout.kcal(goals.calories.goal))
                    divider
                    figure("Exercice", "+\(NutritionReadout.kcal(goals.exerciseCalories))")
                    divider
                    figure(
                        (goals.calories.remaining ?? 0) < 0 ? "Au-delà" : "Restant",
                        NutritionReadout.kcal(goals.calories.remaining.map(abs)),
                        tone: NutritionReadout.goalTone(pct: goals.calories.pct)
                    )
                }
            }
            Text(([day.complete ? "Journée close" : "Journée en cours"] + diet).joined(separator: " · "))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
    }

    private var dial: some View {
        ZStack(alignment: .top) {
            SharpitTickGauge(score: calories?.pct.map { CGFloat(min(max($0, 0), 100)) })
            GeometryReader { geo in
                VStack(spacing: 1) {
                    Text(NutritionReadout.kcal(day.calories))
                        .font(SharpitTypography.gaugeScore)
                        .tracking(SharpitTypography.gaugeScoreTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.numericText())
                    Text("kcal consommées")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SharpitColor.mutedForeground.opacity(0.85))
                }
                .frame(width: geo.size.width)
                .position(x: geo.size.width / 2, y: geo.size.height * SharpitTickGaugeGeometry.readoutTopFraction + 25)
            }
        }
        .frame(width: 230, height: 230 / SharpitTickGaugeGeometry.aspectRatio)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NutritionReadout.kcal(day.calories)) kilocalories consommées")
    }

    private var divider: some View {
        Rectangle().fill(SharpitColor.analysisGrid).frame(width: 1, height: 32)
    }

    private func figure(_ caption: String, _ value: String, tone: Color = SharpitColor.foreground) -> some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(value)
                .font(SharpitTypography.instrument)
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Coach reading

/// The coach's reading on the ink plate, like the verdict on Résumé.
private struct NutritionCoachPlate: View {
    @Environment(ShellRouter.self) private var router
    let reading: V1NutritionCoachReading

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lecture du coach")
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.7))
                Spacer(minLength: 0)
                if case .ready(let ready) = reading, ready.isProvisional {
                    Text("Journée en cours")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.6))
                }
            }
            content
        }
        .padding(SharpitSpacing.md + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
    }

    @ViewBuilder
    private var content: some View {
        switch reading {
        case .ready(let ready):
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                Circle()
                    .fill(NutritionReadout.tone(for: ready.verdict.tone))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(ready.verdict.headline)
                    .font(SharpitTypography.verdict)
                    .tracking(SharpitTypography.verdictTracking)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                ForEach(ready.findings, id: \.self) { finding in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NutritionReadout.jobLabel(finding.job))
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.6))
                        Text(finding.text)
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                Image(systemName: "arrow.turn.down.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.inkAccent)
                    .accessibilityHidden(true)
                Text(ready.action.text)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SharpitSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SharpitColor.inkSurfaceForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
            Button {
                SharpitHaptics.play(.soft)
                router.discussWithCoach(about: CoachDiscuss.describe(.today))
            } label: {
                Label("Discuter avec le coach", systemImage: "bubble.left.and.text.bubble.right")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.inkAccent)
            }
            .buttonStyle(.sharpitPressable)
        case .pending:
            status("Le coach lit ta journée…")
        case .awaitingDayEnd:
            status("La lecture arrive une fois la journée avancée.")
        case .unavailable, .proRequired:
            status("Pas de lecture pour ce jour.")
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(SharpitTypography.body)
            .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.75))
    }
}

// MARK: - Macros

private struct NutritionMacrosSection: View {
    let day: V1NutritionDay

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Macronutriments")
            HStack(spacing: SharpitSpacing.sm) {
                ForEach(NutritionReadout.Macro.allCases, id: \.self) { macro in
                    MacroTile(
                        macro: macro,
                        consumed: macro.consumed(in: day),
                        line: day.goals.map(macro.line(in:)),
                        perKg: perKg(macro)
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            let split = NutritionReadout.energySplit(day)
            if !split.isEmpty {
                EnergySplitBar(split: split)
            }
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
}

private struct MacroTile: View {
    let macro: NutritionReadout.Macro
    let consumed: Double
    let line: V1NutritionMacro?
    let perKg: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: 6) {
                Circle().fill(macro.tone).frame(width: 8, height: 8)
                Text(macro.label)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(consumed.rounded()))")
                    .font(SharpitTypography.data)
                    .tracking(SharpitTypography.dataTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text("g")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            if let line, let goal = line.goal {
                NutritionGoalBar(fill: NutritionReadout.fill(pct: line.pct), tone: macro.tone)
                    .frame(height: 4)
                Text("sur \(Int(goal.rounded())) g")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            if let perKg {
                Text(perKg)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
        }
        .padding(SharpitSpacing.sm + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
    }
}

/// Where the energy came from: one bar split by the macros' kilocalories.
private struct EnergySplitBar: View {
    let split: [(macro: NutritionReadout.Macro, share: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(split, id: \.macro) { part in
                        Rectangle()
                            .fill(part.macro.tone)
                            .frame(width: max(geo.size.width * part.share - 2, 2))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            HStack(spacing: SharpitSpacing.md) {
                ForEach(split, id: \.macro) { part in
                    HStack(spacing: 4) {
                        Circle().fill(part.macro.tone).frame(width: 6, height: 6)
                        Text("\(part.macro.label) \(Int((part.share * 100).rounded())) %")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
            }
        }
        .padding(SharpitSpacing.md)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Répartition de l'énergie")
    }
}

// MARK: - Meals

private struct NutritionMealsSection: View {
    let meals: [V1NutritionMeal]
    let flags: [NutritionEntryFlag]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Repas")
            VStack(spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.element) { index, meal in
                    NavigationLink {
                        NutritionMealView(meal: meal, flags: flags)
                    } label: {
                        MealRow(meal: meal, flagged: flags.contains { flag in
                            meal.entries.contains { flag.matches(meal: meal, entry: $0.name) }
                        })
                    }
                    .buttonStyle(.sharpitPressable)
                    if index < meals.count - 1 {
                        Rectangle()
                            .fill(SharpitColor.analysisGrid)
                            .frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
            }
            .sharpitSurface(.panel)
            .sharpitCardSpecularBorder()
        }
    }
}

private struct MealRow: View {
    let meal: V1NutritionMeal
    let flagged: Bool

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            ZStack {
                Circle().fill(SharpitColor.primary.opacity(0.12)).frame(width: 32, height: 32)
                Image(systemName: NutritionReadout.mealSymbol(meal.name))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.label)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                HStack(spacing: 4) {
                    Text(meal.entries.count == 1 ? "1 aliment" : "\(meal.entries.count) aliments")
                    if flagged {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(SharpitColor.signalCaution)
                            .accessibilityLabel("Aliment signalé par le coach")
                    }
                }
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(NutritionReadout.kcal(meal.calories))
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.foreground)
                Text("kcal")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SharpitSpacing.md)
        .padding(.vertical, SharpitSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The week

private struct NutritionWeekSection: View {
    let history: [V1NutritionHistoryDay]
    let selectedDayId: String
    let onSelectDay: (Date) -> Void

    @State private var picked: Date?

    private var days: [(date: Date, id: String, calories: Double, goal: Double?)] {
        history.compactMap { day in
            guard let calories = day.calories, let date = TrainingDayId.date(day.date) else { return nil }
            return (date, day.date, calories, day.goalCalories)
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

    private var referenceGoal: Double? {
        history.compactMap(\.goalCalories).last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                SharpitEyebrow("Semaine")
                Spacer(minLength: 0)
                Text("Touche un jour pour l'ouvrir")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Chart {
                ForEach(days, id: \.date) { day in
                    BarMark(
                        x: .value("Jour", day.date, unit: .day),
                        y: .value("kcal", day.calories)
                    )
                    .foregroundStyle(tone(for: day))
                    .opacity(day.id == selectedDayId ? 1 : 0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                if let referenceGoal {
                    RuleMark(y: .value("Objectif", referenceGoal))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartXScale(domain: weekDomain)
            .chartXSelection(value: $picked)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                    AxisValueLabel {
                        if let kcal = value.as(Double.self) { Text(NutritionReadout.kcal(kcal)) }
                    }
                }
            }
            .frame(height: 170)
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
            .onChange(of: picked) { _, date in
                guard let date else { return }
                onSelectDay(date)
            }
        }
    }

    private func tone(for day: (date: Date, id: String, calories: Double, goal: Double?)) -> Color {
        guard let goal = day.goal, goal > 0 else { return SharpitColor.signalBase }
        return NutritionReadout.isOnGoal(pct: day.calories / goal * 100)
            ? SharpitColor.signalBase
            : SharpitColor.signalCaution
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
                    .frame(width: max(geo.size.width * fill, fill > 0 ? 4 : 0))
            }
        }
        .animation(SharpitMotion.reveal, value: fill)
        .accessibilityHidden(true)
    }
}
