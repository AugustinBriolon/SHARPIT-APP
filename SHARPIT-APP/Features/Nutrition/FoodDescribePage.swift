import SwiftUI

/// Free-text meal → its dishes, each estimated on its own with editable grams (Pro). A dish of
/// several foods is logged as one named meal (SHARPIT ADR-134); a dish of one food as that food.
struct FoodDescribePage: View {
    let trainingDayId: String
    let meal: FoodLogMeal
    let client: any FoodLogServing
    let tokenProvider: () async throws -> String
    /// The dishes to log, each with the name its foods are grouped under.
    let onAdd: ([DescribedDishDrafts]) -> Void
    /// The Debug screen demo has no Pro store to ask.
    var isProOverride: Bool?

    @Environment(ProStore.self) private var pro: ProStore?
    @State private var description = ""
    @State private var dishes: [DescribedDish] = []
    @State private var phase: Phase = .compose
    @State private var failure: String?
    @State private var selectedMeal: FoodLogMeal
    /// The food whose grams are being set.
    @State private var editing: DescribedFoodLine.ID?
    /// When the meal was eaten: every food of every dish goes out at that time.
    @State private var eatenTime: FoodEatenTime

    init(
        trainingDayId: String,
        meal: FoodLogMeal,
        client: any FoodLogServing,
        tokenProvider: @escaping () async throws -> String,
        isProOverride: Bool? = nil,
        initialDescription: String = "",
        onAdd: @escaping ([DescribedDishDrafts]) -> Void
    ) {
        self.isProOverride = isProOverride
        _description = State(initialValue: initialDescription)
        self.trainingDayId = trainingDayId
        self.meal = meal
        self.client = client
        self.tokenProvider = tokenProvider
        self.onAdd = onAdd
        _selectedMeal = State(initialValue: meal)
        _eatenTime = State(initialValue: FoodEatenTime.initial(meal: meal, trainingDayId: trainingDayId))
    }

    private enum Phase {
        case compose
        case loading
        case review
    }

    private var isPro: Bool { isProOverride ?? (pro?.isPro == true) }
    private var canGenerate: Bool {
        description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && phase != .loading
    }

    private var readyDishes: [DescribedDishDrafts] {
        dishes.compactMap {
            guard var dish = $0.drafts(trainingDayId: trainingDayId, meal: selectedMeal) else { return nil }
            for index in dish.drafts.indices { dish.drafts[index].eatenMinute = eatenTime.sent }
            return dish
        }
    }

    var body: some View {
        Group {
            if !isPro {
                List {
                    Section {
                        SharpitProTeaser(
                            title: String(localized: "Décrire un repas"),
                            message: String(localized: "Décris ce que tu as mangé : SharpIt sépare les plats et estime chacun, à ajuster avant d’ajouter.")
                        )
                        .listRowInsets(EdgeInsets(top: SharpitSpacing.sm, leading: 0, bottom: SharpitSpacing.sm, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                    .sharpitListRows()
                }
                .sharpitGroupedList()
            } else if phase == .review {
                reviewList
            } else {
                composeList
            }
        }
        .navigationTitle("Décrire un repas")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isPro {
                SharpitBareActions {
                    if phase == .review {
                        SharpitPrimaryButton(title: addTitle) {
                            onAdd(readyDishes)
                        }
                        .disabled(readyDishes.isEmpty)
                    } else {
                        SharpitPrimaryButton(title: phase == .loading ? String(localized: "Génération…") : String(localized: "Générer")) {
                            Task { await generate() }
                        }
                        .disabled(!canGenerate)
                    }
                }
            }
        }
    }

    /// The meal goes in whole: « Ajouter au déjeuner », not a count of foods.
    private var addTitle: String { selectedMeal.addTitle }

    private var total: DescribedMealTotal { DescribedMealTotal(dishes.flatMap(\.lines)) }

    private var composeList: some View {
        List {
            Section(
                eyebrow: String(localized: "Ton repas"),
                footer: String(localized: "Exemple : un œuf mayo en entrée, des lasagnes et une mousse au chocolat. Chaque plat est estimé à part.")
            ) {
                TextField(
                    String(localized: "Ce midi j’ai mangé…"),
                    text: $description,
                    axis: .vertical
                )
                .lineLimit(4...10)
                .textInputAutocapitalization(.sentences)
                .disabled(phase == .loading)
                .padding(.vertical, 12)
                .sharpitFieldWell()
                .listRowSeparator(.hidden)
            }
            .sharpitListRows()

            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SharpitColor.signalCaution)
                }
                .sharpitListRows()
            }

            if phase == .loading {
                Section {
                    HStack(spacing: SharpitSpacing.sm) {
                        ProgressView()
                        Text("Estimation des plats…")
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
                .sharpitListRows()
            }
        }
        .sharpitGroupedList()
    }

    private var reviewList: some View {
        List {
            Section {
                FoodMealPicker(meal: $selectedMeal)
                FoodEatenTimePicker(time: $eatenTime)
            }
            .sharpitListRows()
            .onChange(of: selectedMeal) { _, meal in eatenTime.follow(meal: meal, trainingDayId: trainingDayId) }

            // The meal read as one — its energy and what it is made of — before its dishes.
            Section {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    Text(DescribedMealTotal.dishesCaption(dishes.count))
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(NutritionReadout.kcal(total.kcal))
                            .font(SharpitTypography.system(size: 44, weight: .semibold, relativeTo: .largeTitle, digits: true))
                            .tracking(-1.2)
                            .foregroundStyle(SharpitColor.foreground)
                            .contentTransition(.numericText())
                        Text("kcal")
                            .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                            .foregroundStyle(SharpitColor.slate)
                    }
                    NutritionMacroSplitBar(protein: total.protein, carbohydrates: total.carbs, fat: total.fat, height: 8)
                    Text(DescribedMealTotal.macrosCaption(total))
                        .font(SharpitTypography.meta)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.slate)
                }
                .padding(.vertical, SharpitSpacing.xs)
                .accessibilityElement(children: .combine)
            }
            .sharpitListRows()

            // One section a dish: its name as it will be logged, its energy, then its foods.
            ForEach($dishes) { $dish in
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                        TextField("Nom du plat", text: $dish.name, axis: .vertical)
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                            .lineLimit(1...2)
                            .textInputAutocapitalization(.sentences)
                            .accessibilityLabel("Nom du plat")
                        if DescribedMealTotal.hasEstimate(dish.lines) {
                            CliniqueStatusPill(String(localized: "À vérifier"), status: .watch)
                        }
                        Text("\(NutritionReadout.kcal(DescribedMealTotal(dish.lines).kcal)) kcal")
                            .font(SharpitTypography.meta)
                            .monospacedDigit()
                            .foregroundStyle(SharpitColor.slate)
                    }
                    .swipeActions {
                        Button("Supprimer", role: .destructive) { dishes.removeAll { $0.id == dish.id } }
                    }

                    ForEach($dish.lines) { $line in
                        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                            Button {
                                SharpitMotion.run(SharpitMotion.selection) { editing = editing == line.id ? nil : line.id }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.name)
                                            .font(SharpitTypography.body)
                                            .foregroundStyle(SharpitColor.foreground)
                                            .multilineTextAlignment(.leading)
                                        if let caption = line.matchCaption {
                                            Text(caption)
                                                .font(SharpitTypography.meta)
                                                .foregroundStyle(SharpitColor.slate)
                                        }
                                    }
                                    Spacer(minLength: SharpitSpacing.xs)
                                    Text(line.portionCaption)
                                        .font(SharpitTypography.meta)
                                        .monospacedDigit()
                                        .foregroundStyle(SharpitColor.slate)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            if editing == line.id {
                                FoodNumberRow(title: String(localized: "Portion"), unit: "g", text: $line.gramsText)
                                Text(line.macrosCaption)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.slate)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { removeFoods(at: $0, from: dish.id) }
                }
                .sharpitListRows()
            }

            Section {
                Button("Modifier la description") {
                    phase = .compose
                    dishes = []
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
    }

    private func generate() async {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        phase = .loading
        failure = nil
        do {
            let token = try await tokenProvider()
            // Only a request that never arrived is sent again: a server failure here is a model
            // that gave up, and each try is another estimate paid for.
            let described = try await SharpitRetry.run(attempts: 2, retryingOn: { ($0 as? SharpitAPIError) == .transport }) {
                try await client.describeMeal(text, token: token)
            }
            // A server that answers the foods flat names no dish: the athlete's words name it.
            dishes = described.map { DescribedDish(from: $0, fallbackName: text) }
            editing = nil
            phase = .review
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? String(localized: "Impossible de décrire ce repas.")
            phase = .compose
        }
    }

    /// A dish whose last food is removed goes with it.
    private func removeFoods(at offsets: IndexSet, from dishId: DescribedDish.ID) {
        guard let index = dishes.firstIndex(where: { $0.id == dishId }) else { return }
        dishes[index].lines.remove(atOffsets: offsets)
        if dishes[index].lines.isEmpty { dishes.remove(at: index) }
    }
}

/// One dish of a described meal under review: its name, editable, and its foods.
struct DescribedDish: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var lines: [DescribedFoodLine]

    init(from dish: V1DescribedDish, fallbackName: String = "") {
        name = DescribedMealTotal.name(dish.name.isEmpty ? fallbackName : dish.name) ?? ""
        lines = dish.items.map { DescribedFoodLine(from: $0) }
    }

    /// The dish ready to log; nil when none of its foods has a weight.
    func drafts(trainingDayId: String, meal: FoodLogMeal) -> DescribedDishDrafts? {
        let drafts = lines.compactMap { $0.draft(trainingDayId: trainingDayId, meal: meal) }
        return drafts.isEmpty ? nil : DescribedDishDrafts(name: DescribedMealTotal.name(name), drafts: drafts)
    }
}

/// A dish as it is logged: its foods, and the name they are grouped under (nil: on their own).
struct DescribedDishDrafts: Equatable {
    var name: String?
    var drafts: [FoodLogDraft]
}

/// Editable review row: name + grams; macros from per-100 g. Logs a product when matched.
struct DescribedFoodLine: Identifiable, Equatable {
    let id: UUID
    var name: String
    var gramsText: String
    var per100g: V1DescribedFoodPer100g
    var product: V1FoodProduct?
    var match: String?

    init(from food: V1DescribedFood) {
        id = UUID()
        name = food.name
        gramsText = String(Int(food.grams.rounded()))
        per100g = food.per100g
        product = food.product
        match = food.match
    }

    var gramsValue: Double? {
        FoodLogForm.grams(gramsText)
    }

    var matchCaption: String? {
        switch match {
        case "eaten": return String(localized: "Déjà mangé")
        case "own": return String(localized: "Tes aliments")
        case "generic": return String(localized: "Table Ciqual")
        case "product": return String(localized: "Open Food Facts")
        default: return product == nil ? String(localized: "Estimation (sans note)") : nil
        }
    }

    /// « 200 g · 620 kcal », the food on one line.
    var portionCaption: String {
        guard let grams = gramsValue else { return String(localized: "Indique un poids") }
        return "\(FoodPortion.gramsLabel(grams)) · \(NutritionReadout.kcal(per100g.kcal * grams / 100)) kcal"
    }

    var macrosCaption: String {
        guard let grams = gramsValue else { return String(localized: "Indique un poids") }
        let factor = grams / 100
        let kcal = Int((per100g.kcal * factor).rounded())
        let p = Int((per100g.protein * factor).rounded())
        let c = Int((per100g.carbs * factor).rounded())
        let f = Int((per100g.fat * factor).rounded())
        return String(localized: "\(kcal) kcal · P \(p) g · G \(c) g · L \(f) g")
    }

    func draft(trainingDayId: String, meal: FoodLogMeal) -> FoodLogDraft? {
        guard let grams = gramsValue, grams > 0 else { return nil }
        if let product {
            return FoodLogDraft(
                trainingDayId: trainingDayId,
                meal: meal,
                grams: grams,
                source: .product(product)
            )
        }
        let factor = grams / 100
        return FoodLogDraft(
            trainingDayId: trainingDayId,
            meal: meal,
            grams: grams,
            source: .quick(FoodQuickAdd(
                name: name,
                kcal: (per100g.kcal * factor).rounded(),
                protein: ((per100g.protein * factor) * 10).rounded() / 10,
                carbs: ((per100g.carbs * factor) * 10).rounded() / 10,
                fat: ((per100g.fat * factor) * 10).rounded() / 10
            ))
        )
    }
}

/// A described meal as one: its foods' energy and macros at the grams set, a food without a
/// weight counting for nothing.
struct DescribedMealTotal: Equatable {
    var kcal = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0

    init(_ lines: [DescribedFoodLine]) {
        for line in lines {
            guard let grams = line.gramsValue else { continue }
            let factor = grams / 100
            kcal += line.per100g.kcal * factor
            protein += line.per100g.protein * factor
            carbs += line.per100g.carbs * factor
            fat += line.per100g.fat * factor
        }
    }

    /// A food no table knows: its figures are the model's guess.
    static func hasEstimate(_ lines: [DescribedFoodLine]) -> Bool {
        lines.contains { $0.product == nil }
    }

    /// The name a meal is logged under: trimmed, capitalised, 80 characters at most (the
    /// server's limit); nil when nothing is left, and the foods then stand on their own.
    static func name(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String((first.uppercased() + trimmed.dropFirst()).prefix(80))
    }

    static func dishesCaption(_ count: Int) -> String {
        count == 1 ? String(localized: "1 plat") : String(localized: "\(count) plats")
    }

    static func foodsCaption(_ count: Int) -> String {
        count == 1 ? String(localized: "1 aliment") : String(localized: "\(count) aliments")
    }

    static func macrosCaption(_ total: DescribedMealTotal) -> String {
        String(localized: "Glucides \(NutritionReadout.grams(total.carbs)) · Protéines \(NutritionReadout.grams(total.protein)) · Lipides \(NutritionReadout.grams(total.fat))")
    }
}
