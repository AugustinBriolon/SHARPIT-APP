import Charts
import SwiftUI

/// The day's food log, open to every athlete. Read top to bottom like the other day screens:
/// the energy dial, the coach's reading on the ink plate, the macros and where the energy came
/// from, the meals — each with its « + », each opening its own page where a food is edited or
/// taken out — and the week. The log is written here (SHARPIT ADR-061): searched, scanned or
/// typed in. Past days kept in MyFitnessPal come in once, from the athlete's own export file
/// (« Importer depuis MyFitnessPal », docs/adr/0010): the app never signs in to MyFitnessPal.
struct NutritionView: View {
    @State private var store: DayResourceStore<V1NutritionResponse>
    @State private var foodLog: FoodLogStore
    @State private var addRequest: FoodAddRequest?
    @State private var isEditingTargets = false
    @State private var isImporting = false
    @State private var isEditingWeightTarget = false
    @State private var targetWeightKg: Double?
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
            failureMessage: "Ton journal alimentaire n'a pas pu être chargé.",
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
            onChange: { [weak dayStore] in await dayStore?.load() }
        ))
    }

    private var selectedDayId: String { TrainingDayId.today(now: store.selectedDay) }

    var body: some View {
        DayDetailScaffold(
            title: "Nutrition",
            emptySymbol: "fork.knife",
            unavailableTitle: "Nutrition indisponible",
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
                await store.load()
                await foodLog.load(trainingDayId: selectedDayId)
            },
            loadingPlaceholder: NutritionReadout.placeholderResponse
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { addRequest = FoodAddRequest(meal: suggestedMeal) } label: {
                        Label("Ajouter un aliment", systemImage: "plus")
                    }
                    if BarcodeScannerView.isAvailable {
                        Button { addRequest = FoodAddRequest(meal: suggestedMeal, start: .scan) } label: {
                            Label("Scanner un code-barres", systemImage: "barcode.viewfinder")
                        }
                    }
                    Button { isEditingTargets = true } label: {
                        Label("Objectifs nutritionnels", systemImage: "scope")
                    }
                    .disabled(foodLog.phase != .ready)
                    Button { isEditingWeightTarget = true } label: {
                        if let targetWeightKg {
                            Label("Objectif de poids · \(NutritionReadout.kilograms(targetWeightKg))", systemImage: "target")
                        } else {
                            Label("Créer un objectif de poids", systemImage: "plus.circle")
                        }
                    }
                    Divider()
                    Button { isImporting = true } label: {
                        Label("Importer depuis MyFitnessPal", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $isEditingWeightTarget, onDismiss: { Task { await loadWeightTarget() } }) {
            WeightTargetSheet(profileClient: profileClient, tokenProvider: tokenProvider)
        }
        .task { await loadWeightTarget() }
        .onAppear {
            guard opensScanner, !scannerOpened else { return }
            scannerOpened = true
            addRequest = FoodAddRequest(meal: suggestedMeal, start: .scan)
        }
        .task(id: selectedDayId) { await foodLog.load(trainingDayId: selectedDayId) }
        .sheet(item: $addRequest) { FoodAddSheet(store: foodLog, request: $0) }
        .sheet(isPresented: $isEditingTargets) { NutritionTargetsSheet(store: foodLog) }
        .sheet(isPresented: $isImporting) {
            MyFitnessPalImportSheet(store: MyFitnessPalImportStore(
                client: foodLogClient,
                tokenProvider: tokenProvider,
                onImported: { await reloadAfterImport() }
            ))
        }
    }

    /// Imported days rebuild on the server: every day read so far, and the day's own log, are
    /// read again.
    private func reloadAfterImport() async {
        await store.reloadAll()
        await foodLog.load(trainingDayId: selectedDayId)
    }

    /// The meal a food added from the menu goes in: the one the hour suggests today, lunch on
    /// another day.
    private var suggestedMeal: FoodLogMeal {
        Calendar.current.isDateInToday(store.selectedDay) ? FoodLogMeal.suggested(at: .now) : .lunch
    }

    private func loadWeightTarget() async {
        guard let token = try? await tokenProvider(),
              let profile = try? await profileClient.athleteProfile(token: token)
        else { return }
        targetWeightKg = profile.targetWeightKg
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
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            if let day = nutrition.day {
                NutritionDayHeader(diet: nutrition.diet, isComplete: day.complete, dayId: nutrition.trainingDayId)
                NutritionEnergyPlate(day: day, dayId: nutrition.trainingDayId, keptGoal: keptGoal(day))
                coachReading
                NutritionMacrosSection(day: day)
                meals(importedMeals: day.meals)
            } else {
                NutritionDayHeader(diet: nutrition.diet, isComplete: false, dayId: nutrition.trainingDayId)
                if foodLog?.hasEntries != true {
                    NutritionEmptyDayPlate(
                        isToday: isToday,
                        onAdd: { onAdd(FoodAddRequest(meal: suggestedMeal, start: $0)) }
                    )
                }
                meals(importedMeals: [])
            }
            if !nutrition.history.isEmpty {
                NutritionRegularitySection(
                    history: nutrition.history,
                    regularity: nutrition.regularity,
                    selectedDayId: selectedDayId ?? nutrition.trainingDayId
                )
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.bottom, SharpitSpacing.xl)
    }

    private var suggestedMeal: FoodLogMeal { isToday ? FoodLogMeal.suggested(at: .now) : .lunch }

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
        case .none:
            EmptyView()
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
                title: "Lecture du coach",
                message: "Le coach lit ce que tu as mangé face à ton entraînement, et te donne une action concrète."
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

// MARK: - Empty days

/// A day with nothing logged: the empty dial and the next step — scan or search a first food.
private struct NutritionEmptyDayPlate: View {
    let isToday: Bool
    let onAdd: (FoodAddStart) -> Void

    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            ZStack(alignment: .top) {
                SharpitTickGauge(score: nil)
                GeometryReader { geo in
                    VStack(spacing: 4) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(SharpitColor.mutedForeground)
                        Text("0 kcal")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .frame(width: geo.size.width)
                    .position(x: geo.size.width / 2, y: geo.size.height * SharpitTickGaugeGeometry.readoutTopFraction + 22)
                }
            }
            .frame(width: 200, height: 200 / SharpitTickGaugeGeometry.aspectRatio)
            .accessibilityHidden(true)

            VStack(spacing: SharpitSpacing.xxs) {
                Text(isToday ? "Rien de noté pour l'instant" : "Rien de noté ce jour-là")
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text(isToday
                     ? "Note ton premier repas : scanne un emballage ou cherche un aliment. Calories, macros et lecture du coach suivent."
                     : "Ajoute ce que tu as mangé ce jour-là, repas par repas.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: SharpitSpacing.xs) {
                if BarcodeScannerView.isAvailable {
                    capsule("Scanner", symbol: "barcode.viewfinder", tone: SharpitNutritionTone.Action.scan) { onAdd(.scan) }
                }
                capsule("Chercher un aliment", symbol: "magnifyingglass", tone: SharpitColor.primary) { onAdd(.search) }
            }
        }
        .padding(SharpitSpacing.lg)
        .frame(maxWidth: .infinity)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
    }

    private func capsule(_ title: String, symbol: String, tone: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, SharpitSpacing.md)
                .frame(minHeight: SharpitSpacing.minimumTouchTarget)
                .background(tone.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.sharpitPressable)
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

/// The day's energy on the app's own dial, and the three numbers behind it.
private struct NutritionEnergyPlate: View {
    let day: V1NutritionDay
    let dayId: String
    var keptGoal = false

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
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if keptGoal {
                NutritionGoalSeal(dayId: dayId)
                    .padding(SharpitSpacing.sm)
            }
        }
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

/// A day kept on target, sealed. Found by opening a good day, never announced; the first time
/// a day's seal is seen it arrives, then it simply stays.
private struct NutritionGoalSeal: View {
    let dayId: String
    @State private var shown = false

    var body: some View {
        Label("Objectif tenu", systemImage: "checkmark.seal.fill")
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(SharpitColor.primary)
            .padding(.horizontal, SharpitSpacing.xs)
            .padding(.vertical, 4)
            .background(SharpitColor.primary.opacity(0.10), in: Capsule())
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

/// The coach's reading on the ink plate, like the verdict on Résumé.
private struct NutritionCoachPlate: View {
    @Environment(ShellRouter.self) private var router
    let reading: V1NutritionCoachReading
    let dayId: String

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
                router.discussWithCoach(about: CoachDiscuss.describe(.nutrition(trainingDayId: dayId)))
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
                Circle().fill(SharpitNutritionTone.meal(meal.name).opacity(0.14)).frame(width: 32, height: 32)
                Image(systemName: NutritionReadout.mealSymbol(meal.name))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitNutritionTone.mealLabel(meal.name))
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

// MARK: - Header

/// What frames the day before any figure: the diet in force, whether the day is still open, and
/// the coach one tap away — a pill placed with what it discusses, never at the bottom.
private struct NutritionDayHeader: View {
    @Environment(ShellRouter.self) private var router
    let diet: [String]
    let isComplete: Bool
    let dayId: String

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.xs) {
            if diet.isEmpty {
                chip(isComplete ? "Journée close" : "Journée en cours", symbol: isComplete ? "checkmark.circle" : "clock", tone: SharpitColor.mutedForeground)
            } else {
                chip(diet.joined(separator: " · "), symbol: "leaf", tone: SharpitColor.primary)
                    .accessibilityLabel("Régime en cours : \(diet.joined(separator: ", "))")
            }
            Spacer(minLength: 0)
            CoachDiscussButton(title: "Coach") {
                router.discussWithCoach(about: CoachDiscuss.describe(.nutrition(trainingDayId: dayId)))
            }
        }
    }

    private func chip(_ text: String, symbol: String, tone: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(SharpitTypography.bodyEmphasis)
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, SharpitSpacing.sm)
            .padding(.vertical, SharpitSpacing.xs)
            .background(tone.opacity(0.10), in: Capsule())
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
            SharpitEyebrow("Régularité · \(history.count) \(history.count == 1 ? "jour" : "jours")")
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
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                columns
                legend
            }
            .padding(SharpitSpacing.md)
            .sharpitSurface(.panel)
            .sharpitCardSpecularBorder()
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
                        .strokeBorder(SharpitColor.mutedForeground.opacity(0.5), lineWidth: 1.25)
                        .frame(width: 8, height: 8)
                } else {
                    Capsule()
                        .fill(tone(day.adherence))
                        .frame(maxWidth: 14)
                        .frame(height: max(height * min(share, ceiling) / ceiling, 6))
                }
            }
            Text(weekday(day.date))
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? SharpitColor.foreground : SharpitColor.mutedForeground)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .opacity(isSelected || day.adherence == .none ? 1 : 0.85)
    }

    private var legend: some View {
        HStack(spacing: SharpitSpacing.md) {
            legendItem("Dans l'objectif", tone(.onTarget))
            legendItem("En dessous", tone(.under))
            legendItem("Au-dessus", tone(.over))
        }
    }

    private func legendItem(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }

    private func tone(_ adherence: V1CalorieAdherence) -> Color {
        switch adherence {
        case .onTarget: SharpitColor.primary
        case .under: SharpitColor.signalTempo
        case .over: SharpitColor.signalCaution
        case .none: SharpitColor.analysisGrid
        }
    }

    private func weekday(_ dayId: String) -> String {
        guard let date = TrainingDayId.date(dayId) else { return "" }
        return date.sharpitFormatted(.dateTime.weekday(.narrow)).uppercased()
    }

    private var accessibilitySummary: String {
        guard let regularity else { return "Régularité sur 14 jours" }
        return "\(regularity.onTarget) jours dans l'objectif, \(regularity.logged) jours notés sur \(regularity.days)"
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
