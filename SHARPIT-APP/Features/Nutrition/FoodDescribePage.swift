import SwiftUI

/// Free-text meal → distinct foods with editable grams (Pro). Adds them as quick-add entries.
struct FoodDescribePage: View {
    let trainingDayId: String
    let meal: FoodLogMeal
    let client: any FoodLogServing
    let tokenProvider: () async throws -> String
    /// The foods to log, and the name they are logged under as one meal.
    let onAdd: ([FoodLogDraft], String?) -> Void
    /// The Debug screen demo has no Pro store to ask.
    var isProOverride: Bool?

    @Environment(ProStore.self) private var pro: ProStore?
    @State private var description = ""
    @State private var items: [DescribedFoodLine] = []
    @State private var phase: Phase = .compose
    @State private var failure: String?
    @State private var selectedMeal: FoodLogMeal
    /// The foods under the meal's total: folded while every one is a known food.
    @State private var showsFoods = false
    /// The food whose grams are being set.
    @State private var editing: DescribedFoodLine.ID?
    @State private var mealName = ""

    init(
        trainingDayId: String,
        meal: FoodLogMeal,
        client: any FoodLogServing,
        tokenProvider: @escaping () async throws -> String,
        isProOverride: Bool? = nil,
        initialDescription: String = "",
        onAdd: @escaping ([FoodLogDraft], String?) -> Void
    ) {
        self.isProOverride = isProOverride
        _description = State(initialValue: initialDescription)
        self.trainingDayId = trainingDayId
        self.meal = meal
        self.client = client
        self.tokenProvider = tokenProvider
        self.onAdd = onAdd
        _selectedMeal = State(initialValue: meal)
    }

    private enum Phase {
        case compose
        case loading
        case review
    }

    private var isPro: Bool { isProOverride ?? (pro?.isPro == true) }
    private var canGenerate: Bool {
        description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 && phase != .loading
    }

    private var readyDrafts: [FoodLogDraft] {
        items.compactMap { $0.draft(trainingDayId: trainingDayId, meal: selectedMeal) }
    }

    var body: some View {
        Group {
            if !isPro {
                List {
                    Section {
                        SharpitProTeaser(
                            title: String(localized: "Décrire un repas"),
                            message: String(localized: "Décris ce que tu as mangé : SharpIt en tire les aliments et les macros, à ajuster avant d’ajouter.")
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
                SharpitActionDock {
                    if phase == .review {
                        SharpitPrimaryButton(title: addTitle) {
                            onAdd(readyDrafts, DescribedMealTotal.name(mealName))
                        }
                        .disabled(readyDrafts.isEmpty)
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

    private var total: DescribedMealTotal { DescribedMealTotal(items) }

    private var composeList: some View {
        List {
            Section(
                eyebrow: String(localized: "Ton repas"),
                footer: String(localized: "Exemple : ce midi au resto, faux-filet environ 300 g, frites et brocolis.")
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
                        Text("Estimation des aliments…")
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
            }
            .sharpitListRows()

            // The meal read as one — its energy and what it is made of — before its foods: five
            // forms to read back for one kebab was the page's whole cost.
            Section {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    // The meal's name in the log, opened on the athlete's own words.
                    TextField("Nom du repas", text: $mealName, axis: .vertical)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1...2)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Nom du repas")
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

            Section {
                Button {
                    SharpitMotion.run(SharpitMotion.reveal) { showsFoods.toggle() }
                } label: {
                    HStack(spacing: SharpitSpacing.xs) {
                        Text(DescribedMealTotal.foodsCaption(items.count))
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        if DescribedMealTotal.hasEstimate(items) {
                            CliniqueStatusPill(String(localized: "À vérifier"), status: .watch)
                        }
                        Spacer(minLength: SharpitSpacing.xs)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SharpitColor.slate)
                            .rotationEffect(.degrees(showsFoods ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsFoods ? String(localized: "Ouvert") : String(localized: "Fermé"))

                if showsFoods {
                    ForEach($items) { $line in
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
                    .onDelete { items.remove(atOffsets: $0) }
                }
            }
            .sharpitListRows()

            Section {
                Button("Modifier la description") {
                    phase = .compose
                    items = []
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
    }

    private func generate() async {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8 else { return }
        phase = .loading
        failure = nil
        do {
            let token = try await tokenProvider()
            let described = try await SharpitRetry.run {
                try await client.describeMeal(text, token: token)
            }
            items = described.map { DescribedFoodLine(from: $0) }
            // A guessed food is not folded away: its grams are the meal's likeliest error.
            showsFoods = DescribedMealTotal.hasEstimate(items)
            mealName = DescribedMealTotal.name(text) ?? ""
            editing = nil
            phase = .review
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? String(localized: "Impossible de décrire ce repas.")
            phase = .compose
        }
    }
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

    static func foodsCaption(_ count: Int) -> String {
        count == 1 ? String(localized: "1 aliment") : String(localized: "\(count) aliments")
    }

    static func macrosCaption(_ total: DescribedMealTotal) -> String {
        String(localized: "Glucides \(NutritionReadout.grams(total.carbs)) · Protéines \(NutritionReadout.grams(total.protein)) · Lipides \(NutritionReadout.grams(total.fat))")
    }
}
