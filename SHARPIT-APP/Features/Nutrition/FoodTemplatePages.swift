import SwiftUI

// MARK: - Saved meals

/// « Mes repas » (SHARPIT ADR-071): a meal kept under a name, logged whole into the meal the
/// sheet was opened for in one tap. A swipe deletes it, after asking; the days it was logged in
/// keep it.
struct SavedMealsPage: View {
    let store: SavedMealsStore
    let meal: FoodLogMeal
    let onLog: (V1SavedMeal) -> Void

    @State private var pendingDelete: V1SavedMeal?

    var body: some View {
        List {
            switch store.phase {
            case .loading where store.meals.isEmpty:
                Section {
                    HStack(spacing: SharpitSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Chargement…").foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .sharpitListRows()
            case .failed(let message) where store.meals.isEmpty:
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SharpitColor.signalCaution)
                    Button("Réessayer") { Task { await store.load() } }
                }
                .sharpitListRows()
            default:
                if store.meals.isEmpty {
                    Section {} footer: {
                        SharpitListFooter("Aucun repas enregistré. Depuis un repas de ta journée, « Enregistrer ce repas » le garde ici pour le noter d'un geste.")
                    }
                } else {
                    mealsSection
                }
            }
        }
        .sharpitGroupedList()
        .navigationTitle("Mes repas")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .confirmationDialog(
            pendingDelete.map { "Supprimer « \($0.name) » ?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { saved in
            Button("Supprimer le repas", role: .destructive) { Task { await store.delete(saved) } }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Les jours où tu l'as noté le gardent.")
        }
    }

    private var mealsSection: some View {
        Section {
            if let failure = store.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SharpitColor.signalCaution)
            }
            ForEach(store.meals) { saved in
                Button { onLog(saved) } label: { SavedMealRow(saved: saved) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDelete = saved } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
            }
        } header: {
            SharpitEyebrow(meal.label)
        }
        .sharpitListRows()
    }
}

/// A saved meal: its name, its foods and energy, its score.
private struct SavedMealRow: View {
    let saved: V1SavedMeal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.name)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                Text(detail)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                NutritionMacroSplitBar(protein: saved.protein, carbohydrates: saved.carbs, fat: saved.fat, height: 4)
                    .frame(maxWidth: 120)
                    .padding(.top, 3)
            }
            Spacer(minLength: SharpitSpacing.xs)
            VStack(alignment: .trailing, spacing: SharpitSpacing.xs) {
                if let health = saved.health, health.score != nil {
                    FoodHealthBadge(meal: health)
                }
                Text(NutritionReadout.kcal(saved.kcal))
                    .font(SharpitTypography.instrument)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)
                Text("kcal")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ajoute ce repas")
    }

    private var detail: String {
        let count = saved.items.count == 1 ? "1 aliment" : "\(saved.items.count) aliments"
        return "\(count) · P \(Int(saved.protein.rounded())) · G \(Int(saved.carbs.rounded())) · L \(Int(saved.fat.rounded())) g"
    }
}

// MARK: - Recipe

/// A recipe built from other foods (SHARPIT ADR-071): the ingredients weighed raw, the cooked
/// weight and servings if known, the label live as it is built. Saved, it is an own food.
struct FoodRecipePage: View {
    /// The recipe being edited; nil when one is created.
    let recipe: V1FoodProduct?
    let onSave: (FoodRecipeDraft) async throws -> V1FoodProduct
    let onSaved: (V1FoodProduct) -> Void

    @State private var builder: FoodRecipeBuilder
    @State private var search: FoodSearchStore
    @State private var query = ""
    @State private var isSaving = false
    @State private var failure: String?

    init(
        recipe: V1FoodProduct?,
        client: any FoodLogServing,
        tokenProvider: @escaping () async throws -> String,
        onSave: @escaping (FoodRecipeDraft) async throws -> V1FoodProduct,
        onSaved: @escaping (V1FoodProduct) -> Void
    ) {
        self.recipe = recipe
        self.onSave = onSave
        self.onSaved = onSaved
        _builder = State(initialValue: FoodRecipeBuilder(recipe: recipe))
        _search = State(initialValue: FoodSearchStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        List {
            Section(eyebrow: "Recette") {
                TextField("Nom (ex. Bolognaise maison)", text: $builder.name)
                    .textInputAutocapitalization(.sentences)
            }
            .sharpitListRows()

            if FoodSearchStore.isSearchable(query) {
                hitsSection
            }

            Section {
                if builder.lines.isEmpty {
                    Text("Cherche un ingrédient plus haut pour l'ajouter.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                ForEach($builder.lines) { $line in
                    FoodNumberRow(title: line.ingredient.name, unit: "g", text: $line.gramsText)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { builder.remove(line.id) } label: {
                                Label("Retirer", systemImage: "minus.circle")
                            }
                        }
                }
            } header: {
                SharpitEyebrow("Ingrédients, pesés crus")
            }
            .sharpitListRows()

            Section(
                eyebrow: "Plat",
                footer: "Pèse le plat une fois cuit : la cuisson fait perdre de l'eau et concentre le reste. Sans poids cuit, la recette pèse ses ingrédients."
            ) {
                FoodNumberRow(title: "Poids cuit", unit: "g", placeholder: "Optionnel", text: $builder.cookedGramsText)
                FoodNumberRow(title: "Parts", unit: "", placeholder: "Optionnel", text: $builder.servingsText)
            }
            .sharpitListRows()

            if let label = builder.label {
                Section {
                    FoodPortionPreview(nutrients: FoodPortion.Nutrients(
                        kcal: label.kcalPer100g, protein: label.proteinPer100g,
                        carbs: label.carbsPer100g, fat: label.fatPer100g
                    ))
                } header: {
                    SharpitEyebrow("Pour 100 g")
                } footer: {
                    SharpitListFooter(Self.servingLine(label))
                }
                .sharpitListRows()
            }
        }
        .sharpitGroupedList()
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Ajouter un ingrédient"
        )
        .autocorrectionDisabled()
        .onChange(of: query) { _, text in search.setQuery(text) }
        .safeAreaInset(edge: .bottom) {
            SharpitActionDock {
                VStack(spacing: SharpitSpacing.xs) {
                    if let message = failure ?? builder.problem, !builder.lines.isEmpty || failure != nil {
                        Text(message)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(failure == nil ? SharpitColor.mutedForeground : SharpitColor.signalRisk)
                            .multilineTextAlignment(.center)
                    }
                    SharpitPrimaryButton(title: recipe == nil ? "Créer la recette" : "Enregistrer") { save() }
                        .disabled(builder.draft == nil || isSaving)
                }
            }
        }
        .navigationTitle(recipe == nil ? "Créer une recette" : "Modifier la recette")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var hitsSection: some View {
        let hits = Self.hits(search.results, excluding: recipe?.id)
        Section {
            if let message = search.failure {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SharpitColor.signalCaution)
            } else if hits.isEmpty {
                Text(search.isSearching ? "Recherche…" : "Aucun aliment pour « \(query) ».")
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            ForEach(hits) { product in
                Button {
                    builder.add(product)
                    query = ""
                } label: {
                    FoodProductRow(product: product)
                }
                .buttonStyle(.plain)
            }
        } header: {
            SharpitEyebrow("Résultats")
        } footer: {
            FoodSourcesAttribution(products: hits)
        }
        .sharpitListRows()
    }

    private func save() {
        guard let draft = builder.draft, !isSaving else { return }
        isSaving = true
        failure = nil
        Task {
            do {
                onSaved(try await onSave(draft))
            } catch {
                failure = FoodLogStore.failureMessage(error, action: "Recette non enregistrée")
            }
            isSaving = false
        }
    }

    /// Every list of a search as one; a recipe is never its own ingredient.
    static func hits(_ results: V1FoodSearchResults?, excluding id: String?) -> [V1FoodProduct] {
        guard let results else { return [] }
        let all = results.eaten.map(\.product) + results.own + results.generic + results.products
        return Array(all.filter { $0.id != id }.prefix(8))
    }

    static func servingLine(_ label: FoodRecipeLabel) -> String {
        let total = "\(FoodPortion.gramsLabel(label.totalGrams)) en tout"
        guard let serving = label.servingGrams else { return total }
        let kcal = NutritionReadout.kcal(label.kcalPer100g * serving / 100)
        return "\(total) · 1 part · \(FoodPortion.gramsLabel(serving)) · \(kcal) kcal"
    }
}
