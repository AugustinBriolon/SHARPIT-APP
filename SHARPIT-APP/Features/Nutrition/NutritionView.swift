import Charts
import SwiftUI

/// The day's food log, open to every athlete. Read top to bottom like the other day screens:
/// the energy dial, the coach's reading on the ink plate, the macros and where the energy came
/// from, the meals — each with its « + », each opening its own page where a food is edited or
/// taken out — and the week. The log is written here (SHARPIT ADR-061): searched, scanned or
/// typed in. Days imported in the past stay read-only until the athlete logs a food there.
struct NutritionView: View {
    @State private var store: DayResourceStore<V1NutritionResponse>
    @State private var foodLog: FoodLogStore
    @State private var addRequest: FoodAddRequest?
    @State private var isEditingTargets = false
    @State private var scannerOpened = false
    private let opensScanner: Bool
    private let profileClient: any AthleteProfileServing
    private let foodLogClient: any FoodLogServing
    private let tokenProvider: () async throws -> String

    init(
        client: any NutritionServing,
        tokenProvider: @escaping () async throws -> String,
        dataDaysClient: any DataDaysServing = SharpitClient(),
        profileClient: any AthleteProfileServing = AthleteProfileClient(),
        foodLogClient: any FoodLogServing = FoodLogClient(),
        day: Date = .now,
        opensScanner: Bool = false
    ) {
        self.opensScanner = opensScanner
        self.profileClient = profileClient
        self.foodLogClient = foodLogClient
        self.tokenProvider = tokenProvider
        let dayStore = DayResourceStore<V1NutritionResponse>(
            failureMessage: String(localized: "Ton journal alimentaire n'a pas pu être chargé."),
            tokenProvider: tokenProvider,
            day: day,
            dataDays: { try await dataDaysClient.dataDays(domain: .nutrition, from: $0, to: $1, token: $2) },
            fetch: { try await client.nutrition(trainingDayId: $0, token: $1) }
        )
        _store = State(initialValue: dayStore)
        // Every write rebuilds the day on the server: the totals, goals and reading are read
        // back from `/api/v1/nutrition`, never added up here.
        _foodLog = State(initialValue: FoodLogStore(
            trainingDayId: TrainingDayId.today(now: day),
            client: foodLogClient,
            tokenProvider: tokenProvider,
            onChange: { [weak dayStore] in await dayStore?.load() },
            healthWriter: HealthKitWriter()
        ))
    }

    private var selectedDayId: String { TrainingDayId.today(now: store.selectedDay) }

    var body: some View {
        DayDetailScaffold(
            title: String(localized: "Nutrition"),
            emptySymbol: "fork.knife",
            unavailableTitle: String(localized: "Nutrition indisponible"),
            store: store,
            content: { nutrition in
                NutritionSections(
                    nutrition: nutrition,
                    selectedDayId: selectedDayId,
                    foodLog: foodLog,
                    onAdd: { addRequest = $0 }
                )
            },
            refresh: {
                await store.refresh()
                await foodLog.load(trainingDayId: selectedDayId)
            },
            loadingPlaceholder: NutritionReadout.placeholderResponse,
            wash: .watch
        )
        .toolbar {
            // One tap to log a food, wherever the page is scrolled: in the bar, beside the menu.
            ToolbarItem(placement: .topBarTrailing) {
                Button { addRequest = FoodAddRequest(meal: suggestedMeal) } label: {
                    Label("Ajouter un aliment", systemImage: "plus")
                }
            }
            SharpitBarGap()
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if BarcodeScannerView.isAvailable {
                        Button { addRequest = FoodAddRequest(meal: suggestedMeal, start: .scan) } label: {
                            Label("Scanner un code-barres", systemImage: "barcode.viewfinder")
                        }
                    }
                    Button { isEditingTargets = true } label: {
                        Label("Objectifs", systemImage: "scope")
                    }
                    .disabled(foodLog.phase != .ready)
                } label: {
                    Label("Actions", systemImage: "ellipsis")
                }
            }
        }
        .onAppear {
            guard opensScanner, !scannerOpened else { return }
            scannerOpened = true
            addRequest = FoodAddRequest(meal: suggestedMeal, start: .scan)
        }
        .task(id: selectedDayId) { await foodLog.load(trainingDayId: selectedDayId) }
        .sheet(item: $addRequest) { FoodAddSheet(store: foodLog, request: $0) }
        .sheet(isPresented: $isEditingTargets) { NutritionTargetsSheet(store: foodLog, profileClient: profileClient, tokenProvider: tokenProvider) }
    }

    /// The meal a food added from the menu goes in: the one the hour suggests today, lunch on
    /// another day.
    private var suggestedMeal: FoodLogMeal {
        Calendar.current.isDateInToday(store.selectedDay) ? FoodLogMeal.suggested(at: .now) : .lunch
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct NutritionSections: View {
    let nutrition: V1NutritionResponse
    var selectedDayId: String?
    /// The day's own log; nil while a placeholder is drawn.
    var foodLog: FoodLogStore?
    var onAdd: (FoodAddRequest) -> Void = { _ in }

    private var isToday: Bool { nutrition.trainingDayId == TrainingDayId.today(now: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A day with nothing noted is the same page at zero: the goal whole in the ring, the
            // macros empty, every meal offering « Ajouter » — never a different screen.
            let day = NutritionReadout.withGoals(
                nutrition.day ?? NutritionReadout.emptyDay(targets: foodLog?.targets ?? .none),
                targets: foodLog?.targets ?? .none
            )
            NutritionDayHeader(diet: nutrition.diet, isComplete: day.complete)
                .padding(.horizontal, 24)
            NutritionEnergyPlate(day: day, dayId: nutrition.trainingDayId, keptGoal: keptGoal(day))
                .padding(.horizontal, 24)
                .padding(.top, 12)
            NutritionMacrosSection(day: day)
                .padding(.top, 20)
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                if nutrition.day != nil { coachReading }
                meals(importedMeals: day.meals)
                if nutrition.day == nil, foodLog?.hasEntries != true, let copyPreviousDay {
                    Button(action: copyPreviousDay) {
                        Label("Copier la veille", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(CliniqueButtonStyle(kind: .outline))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            if !nutrition.history.isEmpty {
                NutritionRegularitySection(
                    history: nutrition.history,
                    regularity: nutrition.regularity,
                    selectedDayId: selectedDayId ?? nutrition.trainingDayId
                )
                .padding(.horizontal, 24)
                .padding(.top, SharpitSpacing.section)
            }
        }
        // Clears the floating home and add buttons.
        .padding(.bottom, SharpitSpacing.xl + 58)
    }

    private var suggestedMeal: FoodLogMeal { isToday ? FoodLogMeal.suggested(at: .now) : .lunch }

    /// The whole day before, logged into this empty one (SHARPIT ADR-071); nil until a log is held.
    private var copyPreviousDay: (() -> Void)? {
        guard let foodLog else { return nil }
        return { Task { await foodLog.copyFromPreviousDay(nil) } }
    }

    /// The day's own log once read; a day imported from MyFitnessPal keeps its meals read-only, so
    /// nothing logged twice is ever shown (ADR-061: SHARPIT wins a day once it holds an entry).
    @ViewBuilder
    private func meals(importedMeals: [V1NutritionMeal]) -> some View {
        let mode = NutritionMealsMode.resolve(
            foodLogReady: foodLog?.phase == .ready,
            foodLogEntries: foodLog?.entries.count ?? 0,
            importedMeals: importedMeals.count
        )
        switch mode {
        case .foodLog:
            if let foodLog {
                FoodLogMealsSection(store: foodLog, flags: flags) { onAdd(FoodAddRequest(meal: $0)) }
            }
        case .imported:
            NutritionMealsSection(meals: importedMeals, flags: flags)
        case .loading:
            if let foodLog, case .failed(let message) = foodLog.phase {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    Text(message)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                    Button("Réessayer") {
                        Task { await foodLog.load(trainingDayId: foodLog.trainingDayId, force: true) }
                    }
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let foodLog {
                FoodLogMealsSection(store: foodLog, flags: []) { _ in }
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
            }
        }
    }

    /// A day kept on target and done with — a past day, or today once closed — earns its seal.
    private func keptGoal(_ day: V1NutritionDay) -> Bool {
        let isToday = nutrition.trainingDayId == TrainingDayId.today(now: .now)
        guard day.complete || !isToday else { return false }
        return nutrition.history.first(where: { $0.date == nutrition.trainingDayId })?.adherence == .onTarget
    }

    @ViewBuilder
    private var coachReading: some View {
        switch nutrition.coachReading {
        case .proRequired?:
            SharpitProTeaser(
                title: String(localized: "Lecture du coach"),
                message: String(localized: "Le coach lit ce que tu as mangé face à ton entraînement, et te donne une action concrète.")
            )
        case let reading?:
            NutritionCoachPlate(reading: reading, dayId: nutrition.trainingDayId)
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

    /// The coach keys a flag by the stored meal name (`breakfast`) or its label.
    func matches(meal other: FoodLogMeal, entry name: String) -> Bool {
        (meal == other.storedName || meal == other.label) && entry == name
    }
}

// MARK: - Energy

/// The day's energy: what was eaten in a ring, beside the numbers around it — the goal, what
/// exercise added, what is left (the athlete's call, 2026-11-15: eaten inside, remaining beside).
private struct NutritionEnergyPlate: View {
    let day: V1NutritionDay
    let dayId: String
    var keptGoal = false

    private var calories: V1NutritionMacro? { day.goals?.calories }

    var body: some View {
        HStack(spacing: 24) {
            ring
            VStack(spacing: 0) {
                if let goals = day.goals {
                    row(String(localized: "Objectif"), NutritionReadout.kcal(goals.calories.goal))
                    CliniqueDivider()
                    if goals.exerciseCalories > 0 {
                        row(String(localized: "Exercice"), "+ \(NutritionReadout.kcal(goals.exerciseCalories))")
                        CliniqueDivider()
                    }
                }
                if let remaining = calories?.remaining {
                    row(NutritionReadout.remainingCaption(remaining), NutritionReadout.kcal(abs(remaining)))
                }
                // Its own line under the figures: laid over the plate, it covered the ring.
                if keptGoal {
                    CliniqueDivider()
                    NutritionGoalSeal(dayId: dayId)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 9)
                }
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(SharpitColor.divider, lineWidth: 6)
            Circle()
                .trim(from: 0, to: CliniqueRingMath.trim(for: calories?.pct.map { $0 / 100 }))
                .stroke(SharpitColor.pillarNutrition, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(NutritionReadout.kcal(day.calories))
                    .font(SharpitTypography.system(size: 30, weight: .semibold, relativeTo: .title, digits: true))
                    .tracking(-0.8)
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("kcal mangées")
                    .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(SharpitColor.slate)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 120, height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NutritionReadout.kcal(day.calories)) kcal mangées")
    }

    private func row(_ caption: String, _ value: String) -> some View {
        HStack {
            Text(caption)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.slate)
            Spacer(minLength: SharpitSpacing.xs)
            Text(value)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// A day kept on target, sealed. Found by opening a good day, never announced; the first time
/// a day's seal is seen it arrives, then it simply stays.
private struct NutritionGoalSeal: View {
    let dayId: String
    @State private var shown = false

    var body: some View {
        CliniqueStatusPill(String(localized: "Objectif tenu"), status: .good)
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            .onAppear {
                SharpitMotion.run(SharpitMotion.reveal) { shown = true }
                let key = "nutrition.goalSeal.\(dayId)"
                guard !UserDefaults.standard.bool(forKey: key) else { return }
                UserDefaults.standard.set(true, forKey: key)
            }
    }
}

// MARK: - Coach reading

/// The coach's reading in a bordered card: what it says, then what to do.
private struct NutritionCoachPlate: View {
    @Environment(ShellRouter.self) private var router: ShellRouter?
    let reading: V1NutritionCoachReading
    let dayId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Lecture du coach")
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(SharpitColor.slate)
                Spacer(minLength: 0)
                if case .ready(let ready) = reading, ready.isProvisional {
                    Text("Journée en cours")
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(SharpitColor.slate)
                }
                Text("Pro")
                    .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(CliniqueStatus.pro.foreground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(CliniqueStatus.pro.fill, in: Capsule())
                    .overlay(Capsule().strokeBorder(CliniqueStatus.pro.border, lineWidth: 1))
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(SharpitColor.divider, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch reading {
        case .ready(let ready):
            Text("\(ready.verdict.headline) \(ready.action.text)")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                .lineSpacing(4)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ready.findings, id: \.self) { finding in
                (Text("\(NutritionReadout.jobLabel(finding.job)) · ").foregroundStyle(SharpitColor.slate) + Text(finding.text))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                router?.discussWithCoach(about: CoachDiscuss.describe(.nutrition(trainingDayId: dayId)))
            } label: {
                Text("En parler au coach")
                    .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.sharpitPressable)
        case .pending:
            status(String(localized: "Le coach lit ta journée…"))
        case .awaitingDayEnd:
            status(String(localized: "La lecture arrive une fois la journée avancée."))
        case .unavailable, .proRequired:
            status(String(localized: "Pas de lecture pour ce jour."))
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
            .foregroundStyle(SharpitColor.slate)
    }
}

// MARK: - Macros

/// The three macros between two hairlines: eaten over the goal, on a thin bar in its hue.
private struct NutritionMacrosSection: View {
    let day: V1NutritionDay

    var body: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            HStack(alignment: .top, spacing: 14) {
                ForEach([NutritionReadout.Macro.carbohydrates, .protein, .fat], id: \.self) { macro in
                    column(macro, line: day.goals.map(macro.line(in:)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            CliniqueDivider()
        }
    }

    private func column(_ macro: NutritionReadout.Macro, line: V1NutritionMacro?) -> some View {
        VStack(spacing: 6) {
            Text(macro.label)
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(1)
            (Text("\(Int(macro.consumed(in: day).rounded()))")
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                + Text(line?.goal.map { " / \(Int($0.rounded())) g" } ?? " g")
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                .foregroundStyle(SharpitColor.slate))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            SharpitBarTrack(fraction: NutritionReadout.fill(pct: line?.pct), tone: macro.tone)
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Meals

private struct NutritionMealsSection: View {
    let meals: [V1NutritionMeal]
    let flags: [NutritionEntryFlag]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Repas")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            ForEach(Array(meals.enumerated()), id: \.element) { index, meal in
                if index > 0 { CliniqueDivider() }
                NavigationLink {
                    NutritionMealView(meal: meal, flags: flags)
                } label: {
                    MealRow(meal: meal, flagged: flags.contains { flag in
                        meal.entries.contains { flag.matches(meal: meal, entry: $0.name) }
                    })
                }
                .buttonStyle(.sharpitPressable)
            }
        }
    }
}

/// An imported meal on a line: its name over its foods, its energy at the end.
private struct MealRow: View {
    let meal: V1NutritionMeal
    let flagged: Bool

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            NutritionMealGlyph(meal: meal.name)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(meal.label)
                        .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                    if flagged {
                        CliniqueStatusPill(String(localized: "Signalé"), status: .watch)
                            .accessibilityLabel("Aliment signalé par le coach")
                    }
                }
                Text(NutritionReadout.mealLine(meal.entries.map(\.name)))
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
            }
            Spacer(minLength: SharpitSpacing.sm)
            Text(NutritionReadout.kcal(meal.calories))
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Header

/// What frames the day before any figure: the diet in force, or whether the day is still open.
private struct NutritionDayHeader: View {
    let diet: [String]
    let isComplete: Bool

    var body: some View {
        Text(NutritionReadout.dayFrame(diet: diet, isComplete: isComplete))
            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
            .foregroundStyle(SharpitColor.slate)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Regularity

/// Fourteen days against the calorie goal: each day a column reaching its share of the budget,
/// the target band drawn across, the count of days kept on top. It reads — it does not navigate.
private struct NutritionRegularitySection: View {
    let history: [V1NutritionHistoryDay]
    let regularity: V1NutritionRegularity?
    let selectedDayId: String

    /// Share of the budget a column may show; past it the column is simply full.
    private let ceiling = 1.4

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(String(localized: "Régularité · \(history.count) \(history.count == 1 ? "jour" : "jours")"))
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                if let regularity {
                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                        Text("\(regularity.onTarget)")
                            .font(SharpitTypography.gaugeScore)
                            .tracking(SharpitTypography.gaugeScoreTracking)
                            .foregroundStyle(SharpitColor.foreground)
                        Text("jours dans l'objectif")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Spacer(minLength: 0)
                        Text("\(regularity.logged) notés sur \(regularity.days)")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
                columns
                legend
            }
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
        }
    }

    private var columns: some View {
        GeometryReader { geo in
            let height = geo.size.height - 18
            let bandLow = height * (0.9 / ceiling)
            let bandHigh = height * (1.1 / ceiling)
            ZStack(alignment: .bottomLeading) {
                // The target band: within ±10 % of the goal.
                Rectangle()
                    .fill(SharpitColor.primary.opacity(0.08))
                    .frame(height: bandHigh - bandLow)
                    .offset(y: -(bandLow + 18))
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(history, id: \.date) { day in
                        column(day, height: height)
                    }
                }
            }
        }
        .frame(height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func column(_ day: V1NutritionHistoryDay, height: CGFloat) -> some View {
        let isSelected = day.date == selectedDayId
        let share = day.calories.flatMap { calories in day.goalCalories.map { calories / max($0, 1) } } ?? 0
        return VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: height)
                if day.adherence == .none {
                    Circle()
                        .strokeBorder(SharpitColor.slate.opacity(0.5), lineWidth: 1.25)
                        .frame(width: 8, height: 8)
                } else {
                    Capsule()
                        .fill(tone(day.adherence))
                        .frame(maxWidth: 14)
                        .frame(height: max(height * min(share, ceiling) / ceiling, 6))
                }
            }
            Text(weekday(day.date))
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.slate)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .opacity(isSelected || day.adherence == .none ? 1 : 0.85)
    }

    private var legend: some View {
        HStack(spacing: SharpitSpacing.md) {
            legendItem(String(localized: "Dans l'objectif"), tone(.onTarget))
            legendItem(String(localized: "En dessous"), tone(.under))
            legendItem("Au-dessus", tone(.over))
        }
    }

    private func legendItem(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
        }
    }

    private func tone(_ adherence: V1CalorieAdherence) -> Color {
        switch adherence {
        case .onTarget: SharpitColor.primary
        case .under: SharpitColor.signalTempo
        case .over: SharpitColor.signalCaution
        case .none: SharpitColor.divider
        }
    }

    private func weekday(_ dayId: String) -> String {
        guard let date = TrainingDayId.date(dayId) else { return "" }
        return date.sharpitFormatted(.dateTime.weekday(.narrow)).uppercased()
    }

    private var accessibilitySummary: String {
        guard let regularity else { return String(localized: "Régularité sur 14 jours") }
        return String(localized: "\(regularity.onTarget) jours dans l'objectif, \(regularity.logged) jours notés sur \(regularity.days)")
    }
}

/// A goal as a filled track: the share of the goal eaten so far.
struct NutritionGoalBar: View {
    let fill: Double
    let tone: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SharpitColor.divider)
                Capsule()
                    .fill(tone)
                    .frame(width: max(geo.size.width * fill, fill > 0 ? 4 : 0))
            }
        }
        .animation(SharpitMotion.reveal, value: fill)
        .accessibilityHidden(true)
    }
}
