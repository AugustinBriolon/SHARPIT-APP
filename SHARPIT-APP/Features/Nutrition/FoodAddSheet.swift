import SwiftUI

/// How the add-food sheet opens: on the search, or straight on the camera.
enum FoodAddStart: Hashable {
    case search
    case scan
}

/// What the add-food sheet is asked to open, from a meal's « + » or the empty day.
struct FoodAddRequest: Identifiable, Hashable {
    let meal: FoodLogMeal
    var start: FoodAddStart = .search

    var id: String { "\(meal.rawValue)-\(start)" }
}

/// Adds a food to a meal: searched, scanned, picked from the athlete's own foods, typed in or
/// created. One sheet, its pages pushed inside it (HIG: one sheet at a time). The entry shows in the day on « Ajouter » and goes out
/// behind (`FoodLogStore.add`), so the sheet closes at once.
struct FoodAddSheet: View {
    let store: FoodLogStore
    let request: FoodAddRequest

    @State private var search: FoodSearchStore
    @State private var ownFoods: OwnFoodsStore
    @State private var savedMeals: SavedMealsStore
    @State private var path: [FoodAddRoute] = []
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    init(store: FoodLogStore, request: FoodAddRequest) {
        self.store = store
        self.request = request
        _search = State(initialValue: FoodSearchStore(client: store.client, tokenProvider: store.tokenProvider))
        _ownFoods = State(initialValue: OwnFoodsStore(client: store.client, tokenProvider: store.tokenProvider))
        _savedMeals = State(initialValue: SavedMealsStore(client: store.client, tokenProvider: store.tokenProvider))
        _path = State(initialValue: request.start == .scan && BarcodeScannerView.isAvailable ? [.scanner] : [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            FoodSearchPage(
                store: store,
                search: search,
                query: $query,
                onPick: { path.append(.portion($0)) },
                onQuickAdd: { path.append(.quick(name: query)) },
                onCreate: { path.append(.custom(name: query)) },
                onScan: { path.append(.scanner) },
                onDescribe: { path.append(.describe) },
                onOwnFoods: { path.append(.ownFoods) },
                onSavedMeals: { path.append(.savedMeals) },
                onRecipe: { path.append(.recipe(nil)) }
            )
            .navigationTitle(request.meal.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .navigationDestination(for: FoodAddRoute.self, destination: destination)
        }
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }

    @ViewBuilder
    private func destination(_ route: FoodAddRoute) -> some View {
        switch route {
        case .portion(let product):
            FoodPortionPage(
                product: product,
                lastGrams: store.lastGrams(of: product),
                meal: request.meal,
                complete: { await search.fullProduct(of: $0) }
            ) { meal, grams in
                log(FoodLogDraft(trainingDayId: store.trainingDayId, meal: meal, grams: grams, source: .product(product)))
            }
        case .quick(let name):
            FoodQuickAddPage(initialName: name, meal: request.meal) { meal, grams, quick in
                log(FoodLogDraft(trainingDayId: store.trainingDayId, meal: meal, grams: grams, source: .quick(quick)))
            }
        case .custom(let name):
            FoodCustomPage(purpose: .create(name: name)) { draft in
                try await SharpitRetry.run {
                    try await store.client.createCustomFood(draft, token: try await store.tokenProvider())
                }
            } onSaved: { product in
                ownFoods.add(product)
                path.append(.portion(product))
            }
        case .ownFoods:
            OwnFoodsPage(
                store: ownFoods,
                onPick: { path.append(.portion($0)) },
                onEdit: { path.append($0.isRecipe ? .recipe($0) : .editFood($0)) },
                onCreate: { path.append(.custom(name: "")) },
                onDeleted: { store.productDeleted($0) }
            )
        case .editFood(let product):
            FoodCustomPage(purpose: .edit(product)) { draft in
                try await ownFoods.update(product, with: draft)
            } onSaved: { stored in
                store.productChanged(stored)
                path.removeLast()
            }
        case .savedMeals:
            SavedMealsPage(store: savedMeals, meal: request.meal) { saved in
                Task { await store.logSavedMeal(saved, into: request.meal) }
                dismiss()
            }
        case .recipe(let recipe):
            FoodRecipePage(
                recipe: recipe,
                client: store.client,
                tokenProvider: store.tokenProvider,
                onSave: { try await ownFoods.saveRecipe(id: recipe?.id, $0) },
                onSaved: { product in
                    store.productChanged(product)
                    // A new recipe goes on to its portion; an edited one returns to the list.
                    if recipe == nil {
                        path.append(.portion(product))
                    } else {
                        path.removeLast()
                    }
                }
            )
        case .scanner:
            FoodScannerPage(search: search) { outcome in
                switch outcome {
                case .found(let product): path = [.portion(product)]
                case .quickAdd: path = [.quick(name: "")]
                case .create: path = [.custom(name: "")]
                }
            }
        case .describe:
            FoodDescribePage(
                trainingDayId: store.trainingDayId,
                meal: request.meal,
                client: store.client,
                tokenProvider: store.tokenProvider
            ) { drafts in
                logMany(drafts)
            }
        }
    }

    private func log(_ draft: FoodLogDraft) {
        Task { await store.add(draft) }
        dismiss()
    }

    private func logMany(_ drafts: [FoodLogDraft]) {
        Task {
            for draft in drafts {
                await store.add(draft)
            }
        }
        dismiss()
    }
}

enum FoodAddRoute: Hashable {
    case portion(V1FoodProduct)
    case quick(name: String)
    case custom(name: String)
    case scanner
    case describe
    case ownFoods
    case editFood(V1FoodProduct)
    case savedMeals
    /// A recipe to build, or one to edit (SHARPIT ADR-071).
    case recipe(V1FoodProduct?)
}

// MARK: - Search

/// The search: recent foods while nothing is typed, then the athlete's own foods and Open Food
/// Facts' products. Typing in or creating a food is always one row away.
private struct FoodSearchPage: View {
    let store: FoodLogStore
    let search: FoodSearchStore
    @Binding var query: String
    let onPick: (V1FoodProduct) -> Void
    let onQuickAdd: () -> Void
    let onCreate: () -> Void
    let onScan: () -> Void
    let onDescribe: () -> Void
    let onOwnFoods: () -> Void
    let onSavedMeals: () -> Void
    let onRecipe: () -> Void

    private var isSearching: Bool { FoodSearchStore.isSearchable(query) }

    var body: some View {
        List {
            // Shortcuts leave the stage once the athlete is searching — results own the list.
            if !isSearching {
                Section {
                    if BarcodeScannerView.isAvailable {
                        actionRow("Scanner un code-barres", symbol: "barcode.viewfinder", tone: SharpitNutritionTone.Action.scan, action: onScan)
                    }
                    actionRow("Décrire un repas", symbol: "text.bubble", tone: SharpitNutritionTone.Action.describe, action: onDescribe)
                    actionRow("Mes repas", symbol: "bookmark", tone: SharpitNutritionTone.Action.savedMeals, action: onSavedMeals)
                    actionRow("Mes aliments", symbol: "person.crop.square", tone: SharpitNutritionTone.Action.ownFoods, action: onOwnFoods)
                    actionRow("Saisie rapide", symbol: "bolt", tone: SharpitNutritionTone.Action.quickAdd, action: onQuickAdd)
                    actionRow("Créer un aliment", symbol: "plus.square.on.square", tone: SharpitNutritionTone.Action.create, action: onCreate)
                    actionRow("Créer une recette", symbol: "frying.pan", tone: SharpitNutritionTone.Action.recipe, action: onRecipe)
                }
                .sharpitListRows()
            }

            if isSearching {
                searchResults
            } else if !store.recent.isEmpty {
                Section {
                    ForEach(store.recent, id: \.product.id) { recent in
                        productRow(recent.product, grams: recent.lastGrams)
                    }
                } header: {
                    SharpitEyebrow("Récents")
                } footer: {
                    FoodSourcesAttribution(products: store.recent.map(\.product))
                }
                .sharpitListRows()
            }
        }
        .sharpitGroupedList()
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Chercher un aliment"
        )
        .autocorrectionDisabled()
        .onChange(of: query) { _, text in search.setQuery(text) }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let failure = search.failure {
            Section {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SharpitColor.signalCaution)
            }
            .sharpitListRows()
        } else if let results = search.results {
            if !results.eaten.isEmpty {
                Section {
                    ForEach(results.eaten, id: \.product.id) { eaten in
                        productRow(eaten.product, grams: eaten.lastGrams, timesEaten: eaten.timesEaten)
                    }
                } header: {
                    SharpitEyebrow("Déjà mangés")
                } footer: {
                    FoodSourcesAttribution(products: results.eaten.map(\.product))
                }
                .sharpitListRows()
            }
            if !results.own.isEmpty {
                Section(eyebrow: "Mes aliments") {
                    ForEach(results.own) { productRow($0) }
                }
                .sharpitListRows()
            }
            if !results.generic.isEmpty {
                Section {
                    ForEach(results.generic) { productRow($0) }
                } header: {
                    SharpitEyebrow("Aliments de base")
                } footer: {
                    FoodSourcesAttribution(products: results.generic)
                }
                .sharpitListRows()
            }
            if !results.products.isEmpty || results.offUnavailable {
                Section {
                    if results.offUnavailable {
                        Text("Open Food Facts ne répond pas pour l'instant.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    ForEach(results.products) { productRow($0) }
                } header: {
                    SharpitEyebrow("Produits")
                } footer: {
                    FoodSourcesAttribution(products: results.products)
                }
                .sharpitListRows()
            }
            if results.isEmpty && !results.offUnavailable {
                Section {
                    Text("Aucun aliment pour « \(query) ». Saisis-le ou crée-le.")
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                .sharpitListRows()
            }
        } else if search.isSearching {
            Section {
                HStack(spacing: SharpitSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Recherche…").foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .sharpitListRows()
        }
    }

    private func actionRow(_ title: String, symbol: String, tone: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.sm) {
                SharpitRowIcon(symbol: symbol, background: tone)
                Text(title).foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func productRow(_ product: V1FoodProduct, grams: Double? = nil, timesEaten: Int? = nil) -> some View {
        Button { onPick(product) } label: {
            FoodProductRow(product: product, lastGrams: grams, timesEaten: timesEaten)
        }
        .buttonStyle(.plain)
    }
}

/// A food in a list: its name and brand, and its energy per 100 g. A verified food carries the
/// seal after its name (SHARPIT ADR-069).
struct FoodProductRow: View {
    let product: V1FoodProduct
    var lastGrams: Double?
    /// How often it was logged lately, for « Déjà mangés ».
    var timesEaten: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                name.lineLimit(2)
                Text(detail)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                NutritionMacroSplitBar(product: product)
                    .frame(maxWidth: 120)
                    .padding(.top, 3)
                FoodDietConflictLine(health: product.health)
                    .padding(.top, 2)
            }
            Spacer(minLength: SharpitSpacing.xs)
            VStack(alignment: .trailing, spacing: SharpitSpacing.xs) {
                FoodHealthBadge(health: product.health)
                Text(NutritionReadout.kcal(product.kcalPer100g))
                    .font(SharpitTypography.instrument)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)
                Text("kcal/100 g")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var name: Text {
        let title = Text(product.name)
            .font(SharpitTypography.body)
            .foregroundStyle(SharpitColor.foreground)
        guard product.isVerified else { return title }
        let seal = Text(Image(systemName: "checkmark.seal.fill"))
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.primary)
            .accessibilityLabel(product.verifiedLabel ?? "Vérifié")
        return Text("\(title) \(seal)")
    }

    private var detail: String {
        var parts: [String] = []
        if let timesEaten, timesEaten > 0 { parts.append("\(timesEaten) fois") }
        if let brand = product.brand, !brand.isEmpty { parts.append(brand) }
        if let lastGrams { parts.append("Dernière fois \(FoodPortion.gramsLabel(lastGrams))") }
        if product.source == "CUSTOM" { parts.append("Mon aliment") }
        if product.isCiqual { parts.append("Aliment de base") }
        return parts.isEmpty ? "Pour 100 g" : parts.joined(separator: " · ")
    }
}

// MARK: - Portion

/// How much of a food, and in which meal: the grams with a few presets, what they bring, « Ajouter ».
struct FoodPortionPage: View {
    let lastGrams: Double?
    /// Reads the whole product when the one picked came from a search hit (its additives).
    let complete: ((V1FoodProduct) async -> V1FoodProduct?)?
    let onAdd: (FoodLogMeal, Double) -> Void

    @State private var product: V1FoodProduct
    @State private var isCompleting = false
    @State private var gramsText: String
    @State private var meal: FoodLogMeal
    @FocusState private var isGramsFocused: Bool

    init(
        product: V1FoodProduct,
        lastGrams: Double?,
        meal: FoodLogMeal,
        complete: ((V1FoodProduct) async -> V1FoodProduct?)? = nil,
        onAdd: @escaping (FoodLogMeal, Double) -> Void
    ) {
        _product = State(initialValue: product)
        self.lastGrams = lastGrams
        self.complete = complete
        self.onAdd = onAdd
        _gramsText = State(initialValue: FoodPortion.editableFigure(FoodPortion.initialGrams(for: product, lastGrams: lastGrams)))
        _meal = State(initialValue: meal)
    }

    private var grams: Double? { FoodLogForm.grams(gramsText) }

    private var scoredHealth: V1FoodHealth? {
        guard let health = product.health, health.coverage != .none else { return nil }
        return health
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(SharpitTypography.cardTitle)
                        .tracking(SharpitTypography.cardTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    if let brand = product.brand, !brand.isEmpty {
                        Text(brand)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                FoodPortionPreview(nutrients: FoodPortion.nutrients(of: product, grams: grams ?? 0))
            }
            .sharpitListRows()

            if let health = scoredHealth {
                Section {
                    FoodHealthScoreHeader(health: health)
                    FoodDietConflictLine(health: health)
                } header: {
                    SharpitEyebrow("Score Sharpit")
                } footer: {
                    SharpitListFooter("Le détail du score est plus bas.")
                }
                .sharpitListRows()
            }

            Section {
                FoodGramsRows(
                    text: $gramsText,
                    presets: FoodPortion.presets(for: product, lastGrams: lastGrams),
                    isFocused: $isGramsFocused
                )
                if grams == nil {
                    Text("Entre une quantité entre 1 et 5 000 g.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
            } header: {
                SharpitEyebrow("Quantité")
            } footer: {
                SharpitListFooter("Pour 100 g : \(NutritionReadout.kcal(product.kcalPer100g)) kcal · P \(FoodPortion.figure(product.proteinPer100g)) · G \(FoodPortion.figure(product.carbsPer100g)) · L \(FoodPortion.figure(product.fatPer100g)) g")
            }
            .sharpitListRows()

            Section {
                FoodMealPicker(meal: $meal)
            }
            .sharpitListRows()

            if let health = scoredHealth {
                FoodHealthSections(health: health, isCompleting: isCompleting, showsScoreHeader: false)
            }

            if V1FoodProduct.attribution(for: [product]) != nil {
                Section {} footer: { FoodSourcesAttribution(products: [product]) }
            }
        }
        .sharpitGroupedList()
        .task { await completeIfSummary() }
        .safeAreaInset(edge: .bottom) {
            SharpitActionDock {
                SharpitPrimaryButton(title: "Ajouter") { add() }
                    .disabled(grams == nil)
            }
        }
        .navigationTitle("Portion")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        guard let grams else { return }
        onAdd(meal, grams)
    }

    private func completeIfSummary() async {
        guard let complete, product.health?.detail == .summary, !isCompleting else { return }
        isCompleting = true
        if let full = await complete(product) { product = full }
        isCompleting = false
    }
}

// MARK: - Quick add

/// A food typed in by hand: its name and energy, the macros if known.
private struct FoodQuickAddPage: View {
    let onAdd: (FoodLogMeal, Double, FoodQuickAdd) -> Void

    @State private var name: String
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var gramsText = ""
    @State private var meal: FoodLogMeal

    init(initialName: String, meal: FoodLogMeal, onAdd: @escaping (FoodLogMeal, Double, FoodQuickAdd) -> Void) {
        self.onAdd = onAdd
        _name = State(initialValue: initialName.trimmingCharacters(in: .whitespacesAndNewlines))
        _meal = State(initialValue: meal)
    }

    /// The portion's weight is optional: the energy typed is the whole portion's either way.
    private static let defaultGrams = 100.0

    private var entry: (grams: Double, quick: FoodQuickAdd)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120,
              let kcalValue = FoodLogForm.amount(kcal, in: 0...10_000),
              let proteinValue = FoodLogForm.optionalAmount(protein, in: 0...1000),
              let carbsValue = FoodLogForm.optionalAmount(carbs, in: 0...1000),
              let fatValue = FoodLogForm.optionalAmount(fat, in: 0...1000)
        else { return nil }
        let grams = gramsText.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultGrams : FoodLogForm.grams(gramsText)
        guard let grams else { return nil }
        return (grams, FoodQuickAdd(name: trimmed, kcal: kcalValue, protein: proteinValue, carbs: carbsValue, fat: fatValue))
    }

    var body: some View {
        List {
            Section(eyebrow: "Aliment") {
                TextField("Nom (ex. Sandwich jambon-beurre)", text: $name)
                    .textInputAutocapitalization(.sentences)
                FoodNumberRow(title: "Énergie", unit: "kcal", text: $kcal)
            }
            .sharpitListRows()

            Section(
                eyebrow: "Macronutriments",
                footer: "Optionnels. Les valeurs sont celles de la portion entière."
            ) {
                FoodNumberRow(title: "Protéines", unit: "g", text: $protein)
                FoodNumberRow(title: "Glucides", unit: "g", text: $carbs)
                FoodNumberRow(title: "Lipides", unit: "g", text: $fat)
                FoodNumberRow(title: "Poids de la portion", unit: "g", placeholder: "Optionnel", text: $gramsText)
            }
            .sharpitListRows()

            Section {
                FoodMealPicker(meal: $meal)
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .safeAreaInset(edge: .bottom) {
            SharpitActionDock {
                SharpitPrimaryButton(title: "Ajouter") {
                    guard let entry else { return }
                    onAdd(meal, entry.grams, entry.quick)
                }
                .disabled(entry == nil)
            }
        }
        .navigationTitle("Saisie rapide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A labelled number with its unit, typed on the decimal pad.
struct FoodNumberRow: View {
    let title: String
    let unit: String
    var placeholder = "0"
    @Binding var text: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: SharpitSpacing.xxs) {
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(unit)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }
}

/// The custom-food form as typed: names within the server's lengths, figures per 100 g within
/// its ranges, empty macros as zero, empty options as not given.
nonisolated enum FoodCustomForm {
    static func draft(
        name: String, brand: String, kcal: String, protein: String, carbs: String, fat: String,
        fiber: String, sugar: String, salt: String, saturatedFat: String, serving: String
    ) -> FoodCustomDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120, trimmedBrand.count <= 80,
              let kcalValue = FoodLogForm.amount(kcal, in: 0...1000),
              let proteinValue = FoodLogForm.amount(protein.isEmpty ? "0" : protein, in: 0...1000),
              let carbsValue = FoodLogForm.amount(carbs.isEmpty ? "0" : carbs, in: 0...1000),
              let fatValue = FoodLogForm.amount(fat.isEmpty ? "0" : fat, in: 0...1000),
              let fiberValue = FoodLogForm.optionalAmount(fiber, in: 0...1000),
              let sugarValue = FoodLogForm.optionalAmount(sugar, in: 0...1000),
              let saltValue = FoodLogForm.optionalAmount(salt, in: 0...1000),
              let saturatedFatValue = FoodLogForm.optionalAmount(saturatedFat, in: 0...1000)
        else { return nil }
        let servingValue: Double?? = serving.trimmingCharacters(in: .whitespaces).isEmpty
            ? .some(nil) : FoodLogForm.grams(serving).map { .some($0) }
        guard let servingValue else { return nil }
        return FoodCustomDraft(
            name: trimmed,
            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
            kcalPer100g: kcalValue,
            proteinPer100g: proteinValue,
            carbsPer100g: carbsValue,
            fatPer100g: fatValue,
            fiberPer100g: fiberValue,
            sugarPer100g: sugarValue,
            saltPer100g: saltValue,
            saturatedFatPer100g: saturatedFatValue,
            servingGrams: servingValue
        )
    }
}

// MARK: - Scanner

/// What the athlete chose after a scan.
enum FoodScanOutcome {
    case found(V1FoodProduct)
    case quickAdd
    case create
}

/// The camera, full page. A code read is looked up at once; one Open Food Facts does not know
/// offers to type the food in or create it, never a dead end.
private struct FoodScannerPage: View {
    let search: FoodSearchStore
    let onOutcome: (FoodScanOutcome) -> Void

    @State private var isLookingUp = false
    @State private var isUnknown = false
    @State private var failure: String?
    @State private var lastCode: String?

    var body: some View {
        BarcodeScannerView { code in
            guard !isLookingUp, !isUnknown else { return }
            Task { await lookUp(code) }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) { status }
        .navigationTitle("Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Produit inconnu", isPresented: $isUnknown) {
            Button("Saisie rapide") { onOutcome(.quickAdd) }
            Button("Créer l'aliment") { onOutcome(.create) }
            Button("Scanner un autre", role: .cancel) {}
        } message: {
            Text("Open Food Facts ne connaît pas ce code-barres. Saisis l'aliment rapidement ou crée-le avec son étiquette.")
        }
    }

    private var status: some View {
        HStack(spacing: SharpitSpacing.xs) {
            if isLookingUp {
                ProgressView().controlSize(.small)
                Text("Recherche du produit…")
            } else if let failure {
                Image(systemName: "exclamationmark.triangle")
                Text(failure)
            } else {
                Image(systemName: "barcode.viewfinder")
                Text("Vise le code-barres de l'emballage.")
            }
        }
        .font(SharpitTypography.meta.weight(.medium))
        .foregroundStyle(SharpitColor.foreground)
        .padding(.horizontal, SharpitSpacing.md)
        .padding(.vertical, SharpitSpacing.sm)
        .sharpitGlassCapsule()
        .padding(.bottom, SharpitSpacing.lg)
        .padding(.horizontal, SharpitSpacing.pageInset)
    }

    private func lookUp(_ code: String) async {
        isLookingUp = true
        failure = nil
        lastCode = code
        let outcome = await search.lookUp(barcode: code)
        isLookingUp = false
        switch outcome {
        case .found(let product):
            onOutcome(.found(product))
        case .unknown:
            isUnknown = true
        case .failed(let message):
            failure = message
        }
    }
}
