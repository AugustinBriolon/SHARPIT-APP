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
    /// The meal the food goes into: the one asked for, changed from the title.
    @State private var meal: FoodLogMeal
    @Environment(\.dismiss) private var dismiss

    init(store: FoodLogStore, request: FoodAddRequest) {
        self.store = store
        self.request = request
        _meal = State(initialValue: request.meal)
        _search = State(initialValue: FoodSearchStore(client: store.client, tokenProvider: store.tokenProvider))
        _ownFoods = State(initialValue: OwnFoodsStore(client: store.client, tokenProvider: store.tokenProvider))
        _savedMeals = State(initialValue: SavedMealsStore(client: store.client, tokenProvider: store.tokenProvider))
        _path = State(initialValue: request.start == .scan && BarcodeScannerView.isAvailable ? [.scanner] : [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            FoodSearchPage(
                meal: $meal,
                onClose: { dismiss() },
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
            .navigationTitle(meal.label)
            // The page carries its own name and its way out; pushed pages keep the bar.
            .toolbar(.hidden, for: .navigationBar)
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
                meal: meal,
                complete: { await search.fullProduct(of: $0) }
            ) { meal, grams in
                log(FoodLogDraft(trainingDayId: store.trainingDayId, meal: meal, grams: grams, source: .product(product)))
            }
        case .quick(let name):
            FoodQuickAddPage(initialName: name, meal: meal) { meal, grams, quick in
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
                ownFoods.update(product, with: draft)
            } onSaved: { stored in
                store.productChanged(stored)
                path.removeLast()
            }
        case .savedMeals:
            SavedMealsPage(store: savedMeals, meal: meal) { saved in
                Task { await store.logSavedMeal(saved, into: meal) }
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
                meal: meal,
                client: store.client,
                tokenProvider: store.tokenProvider
            ) { drafts, name in
                logMany(drafts, as: name)
            }
        }
    }

    private func log(_ draft: FoodLogDraft) {
        Task { await store.add(draft) }
        dismiss()
    }

    private func logMany(_ drafts: [FoodLogDraft], as name: String?) {
        Task { await store.add(drafts, groupLabel: name) }
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
    private enum Filter { case all, recent }

    @Binding var meal: FoodLogMeal
    let onClose: () -> Void
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

    @State private var filter = Filter.all

    private var isSearching: Bool { FoodSearchStore.isSearchable(query) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    // The title is the meal, and the way to another one.
                    Menu {
                        Picker("Repas", selection: $meal) {
                            ForEach(FoodLogMeal.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(meal.label)
                                .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2))
                                .tracking(-0.4)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SharpitColor.slate)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .accessibilityLabel("Repas")
                    .accessibilityValue(meal.label)
                    .accessibilityHint("Change le repas")
                    Spacer(minLength: SharpitSpacing.xs)
                    circleButton("xmark", String(localized: "Fermer"), size: 13, action: onClose)
                }
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(SharpitColor.slate)
                            .accessibilityHidden(true)
                        TextField("Chercher un aliment", text: $query)
                            .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(SharpitColor.tile, in: Capsule())
                    if BarcodeScannerView.isAvailable {
                        circleButton("barcode.viewfinder", String(localized: "Scanner un code-barres"), size: 18, action: onScan)
                    }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        chip(String(localized: "Tous"), isOn: filter == .all) { filter = .all }
                        chip(String(localized: "Récents"), isOn: filter == .recent) { filter = .recent }
                        chip(String(localized: "Mes repas"), isOn: false, action: onSavedMeals)
                        chip(String(localized: "Mes aliments"), isOn: false, action: onOwnFoods)
                        Menu {
                            Button(String(localized: "Décrire un repas"), systemImage: "text.bubble", action: onDescribe)
                            Button(String(localized: "Saisie rapide"), systemImage: "bolt", action: onQuickAdd)
                            Button(String(localized: "Créer un aliment"), systemImage: "plus.square.on.square", action: onCreate)
                            Button(String(localized: "Créer une recette"), systemImage: "frying.pan", action: onRecipe)
                        } label: {
                            chipLabel(String(localized: "Autre…"), isOn: false)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()

                VStack(alignment: .leading, spacing: 0) {
                    if isSearching {
                        searchResults
                    } else if !store.recent.isEmpty {
                        group(String(localized: "Récents"), attribution: store.recent.map(\.product)) {
                            ForEach(store.recent, id: \.product.id) { recent in
                                productRow(recent.product, grams: recent.lastGrams)
                            }
                        }
                    } else {
                        note(String(localized: "Cherche un aliment, scanne un emballage ou décris ton repas."))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, SharpitSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SharpitColor.card)
        .onChange(of: query) { _, text in search.setQuery(text) }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let failure = search.failure {
            Label(failure, systemImage: "exclamationmark.triangle")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.signalCaution)
                .padding(.vertical, 14)
        } else if let results = search.results {
            if !results.eaten.isEmpty {
                group(String(localized: "Déjà mangés"), attribution: results.eaten.map(\.product)) {
                    ForEach(results.eaten, id: \.product.id) { eaten in
                        productRow(eaten.product, grams: eaten.lastGrams, timesEaten: eaten.timesEaten)
                    }
                }
            }
            if filter == .all {
                if !results.own.isEmpty {
                    group(String(localized: "Mes aliments"), attribution: []) {
                        ForEach(results.own) { productRow($0) }
                    }
                }
                if !results.generic.isEmpty {
                    group(String(localized: "Aliments de base"), attribution: results.generic) {
                        ForEach(results.generic) { productRow($0) }
                    }
                }
                if !results.products.isEmpty || results.offUnavailable {
                    group(String(localized: "Produits"), attribution: results.products) {
                        if results.offUnavailable {
                            note(String(localized: "Open Food Facts ne répond pas pour l'instant."))
                        }
                        ForEach(results.products) { productRow($0) }
                    }
                }
            }
            if results.isEmpty && !results.offUnavailable {
                note(String(localized: "Aucun aliment pour « \(query) ». Saisis-le ou crée-le."))
            } else if filter == .recent, results.eaten.isEmpty {
                note(String(localized: "Rien de déjà mangé pour « \(query) »."))
            }
        } else if search.isSearching {
            HStack(spacing: SharpitSpacing.xs) {
                ProgressView().controlSize(.small)
                Text("Recherche…").foregroundStyle(SharpitColor.slate)
            }
            .padding(.vertical, 14)
        }
    }

    /// A named run of foods, split by hairlines, with whose data it is under it.
    private func group<Rows: View>(_ title: String, attribution: [V1FoodProduct], @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                .foregroundStyle(SharpitColor.slate)
                .padding(.top, 10)
                .padding(.bottom, 2)
            Group(subviews: rows()) { subviews in
                ForEach(subviews) { row in
                    if row.id != subviews.first?.id { CliniqueDivider() }
                    row
                }
            }
            FoodSourcesAttribution(products: attribution)
                .padding(.top, 4)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
            .foregroundStyle(SharpitColor.slate)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 14)
    }

    private func circleButton(_ symbol: String, _ label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 52, height: 52)
                .background(SharpitColor.tile, in: Circle())
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(label)
    }

    private func chipLabel(_ title: String, isOn: Bool) -> some View {
        Text(title)
            .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(isOn ? SharpitColor.primaryForeground : SharpitColor.foreground)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(isOn ? SharpitColor.primary : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(SharpitColor.divider, lineWidth: isOn ? 0 : 1))
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, isOn: isOn) }
            .buttonStyle(.sharpitPressable)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func productRow(_ product: V1FoodProduct, grams: Double? = nil, timesEaten: Int? = nil) -> some View {
        Button { onPick(product) } label: {
            FoodProductRow(product: product, lastGrams: grams, timesEaten: timesEaten)
                .padding(.vertical, 12)
        }
        .buttonStyle(.sharpitPressable)
    }
}

/// A food in a list: its name, its energy per 100 g and what it is, its score at the trailing edge. A verified food carries the
/// seal after its name (SHARPIT ADR-069).
struct FoodProductRow: View {
    let product: V1FoodProduct
    var lastGrams: Double?
    /// How often it was logged lately, for « Déjà mangés ».
    var timesEaten: Int?

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                name.lineLimit(2).multilineTextAlignment(.leading)
                Text(detail)
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
                FoodDietConflictLine(health: product.health)
            }
            Spacer(minLength: SharpitSpacing.xs)
            FoodHealthBadge(health: product.health)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var name: Text {
        let title = Text(product.name)
            .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
            .foregroundStyle(SharpitColor.foreground)
        guard product.isVerified else { return title }
        let seal = Text(Image(systemName: "checkmark.seal.fill"))
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.primary)
            .accessibilityLabel(product.verifiedLabel ?? String(localized: "Vérifié"))
        return Text("\(title) \(seal)")
    }

    private var detail: String {
        var parts: [String] = []
        if let timesEaten, timesEaten > 0 { parts.append("\(timesEaten) fois") }
        if let brand = product.brand, !brand.isEmpty { parts.append(brand) }
        if let lastGrams { parts.append(String(localized: "Dernière fois \(FoodPortion.gramsLabel(lastGrams))")) }
        if product.source == "CUSTOM" { parts.append(String(localized: "Mon aliment")) }
        if product.isCiqual { parts.append(String(localized: "Aliment de base")) }
        // Its energy opens the line, as the mock-up reads it: « 100 g · 124 kcal ».
        parts.insert(String(localized: "100 g · \(NutritionReadout.kcal(product.kcalPer100g)) kcal"), at: 0)
        return parts.joined(separator: " · ")
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
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                            .font(SharpitTypography.system(size: 22, weight: .semibold, relativeTo: .title2))
                            .tracking(-0.4)
                            .foregroundStyle(SharpitColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        if let brand = product.brand, !brand.isEmpty {
                            Text(brand)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.slate)
                        }
                    }
                    Spacer(minLength: 0)
                    if scoredHealth != nil {
                        FoodHealthBadge(health: product.health)
                    }
                }
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
            }
            .sharpitListRows()
            .listRowSeparator(.hidden)

            Section {
                FoodNutrientLines(
                    nutrients: FoodPortion.nutrients(of: product, grams: grams ?? 0),
                    fiber: product.fiberPer100g.map { $0 * (grams ?? 0) / 100 }
                )
            } header: {
                SharpitEyebrow(String(localized: "Pour \(FoodPortion.gramsLabel(grams ?? 0))"))
            }
            .sharpitListRows()

            Section {
                FoodMealPicker(meal: $meal)
                if let health = scoredHealth {
                    FoodDietConflictLine(health: health)
                }
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
                Button { add() } label: {
                    Text(meal.addTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                .disabled(grams == nil)
            }
        }
        .navigationTitle("Portion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Text("") } }
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
            Section(eyebrow: String(localized: "Aliment")) {
                TextField("Nom (ex. Sandwich jambon-beurre)", text: $name)
                    .textInputAutocapitalization(.sentences)
                FoodNumberRow(title: String(localized: "Énergie"), unit: "kcal", text: $kcal)
            }
            .sharpitListRows()

            Section(
                eyebrow: String(localized: "Macronutriments"),
                footer: String(localized: "Optionnels. Les valeurs sont celles de la portion entière.")
            ) {
                FoodNumberRow(title: String(localized: "Protéines"), unit: "g", text: $protein)
                FoodNumberRow(title: String(localized: "Glucides"), unit: "g", text: $carbs)
                FoodNumberRow(title: String(localized: "Lipides"), unit: "g", text: $fat)
                FoodNumberRow(title: String(localized: "Poids de la portion"), unit: "g", placeholder: String(localized: "Optionnel"), text: $gramsText)
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
                SharpitPrimaryButton(title: String(localized: "Ajouter")) {
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
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                Text(unit)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
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
        .font(SharpitTypography.meta.weight(.regular))
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
