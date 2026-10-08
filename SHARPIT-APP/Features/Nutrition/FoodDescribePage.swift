import SwiftUI

/// Free-text meal → distinct foods with editable grams (Pro). Adds them as quick-add entries.
struct FoodDescribePage: View {
    let trainingDayId: String
    let meal: FoodLogMeal
    let client: any FoodLogServing
    let tokenProvider: () async throws -> String
    let onAdd: ([FoodLogDraft]) -> Void

    @Environment(ProStore.self) private var pro: ProStore?
    @State private var description = ""
    @State private var items: [DescribedFoodLine] = []
    @State private var phase: Phase = .compose
    @State private var failure: String?
    @State private var selectedMeal: FoodLogMeal

    init(
        trainingDayId: String,
        meal: FoodLogMeal,
        client: any FoodLogServing,
        tokenProvider: @escaping () async throws -> String,
        onAdd: @escaping ([FoodLogDraft]) -> Void
    ) {
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

    private var isPro: Bool { pro?.isPro == true }
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
                            title: "Décrire un repas",
                            message: "Décris ce que tu as mangé : SharpIt en tire les aliments et les macros, à ajuster avant d’ajouter."
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
                            onAdd(readyDrafts)
                        }
                        .disabled(readyDrafts.isEmpty)
                    } else {
                        SharpitPrimaryButton(title: phase == .loading ? "Génération…" : "Générer") {
                            Task { await generate() }
                        }
                        .disabled(!canGenerate)
                    }
                }
            }
        }
    }

    private var addTitle: String {
        let count = readyDrafts.count
        return count <= 1 ? "Ajouter au repas" : "Ajouter les \(count) aliments"
    }

    private var composeList: some View {
        List {
            Section(
                eyebrow: "Ton repas",
                footer: "Exemple : ce midi au resto, faux-filet environ 300 g, frites et brocolis."
            ) {
                TextField(
                    "Ce midi j’ai mangé…",
                    text: $description,
                    axis: .vertical
                )
                .lineLimit(4...10)
                .textInputAutocapitalization(.sentences)
                .disabled(phase == .loading)
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
                            .foregroundStyle(SharpitColor.mutedForeground)
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

            Section(
                eyebrow: "Aliments",
                footer: "Ajuste les grammes ; les macros suivent. Un aliment connu garde sa note. Glisse pour retirer une ligne."
            ) {
                ForEach($items) { $line in
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                            Text(line.name)
                                .font(SharpitTypography.body.weight(.semibold))
                            Spacer(minLength: 0)
                            if let health = line.product?.health, health.coverage != .none {
                                FoodHealthBadge(health: health)
                            }
                        }
                        if let caption = line.matchCaption {
                            Text(caption)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                        FoodNumberRow(title: "Portion", unit: "g", text: $line.gramsText)
                        Text(line.macrosCaption)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { items.remove(atOffsets: $0) }
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
            phase = .review
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? "Impossible de décrire ce repas."
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
        case "eaten": return "Déjà mangé"
        case "own": return "Tes aliments"
        case "generic": return "Table Ciqual"
        case "product": return "Open Food Facts"
        default: return product == nil ? "Estimation (sans note)" : nil
        }
    }

    var macrosCaption: String {
        guard let grams = gramsValue else { return "Indique un poids" }
        let factor = grams / 100
        let kcal = Int((per100g.kcal * factor).rounded())
        let p = Int((per100g.protein * factor).rounded())
        let c = Int((per100g.carbs * factor).rounded())
        let f = Int((per100g.fat * factor).rounded())
        return "\(kcal) kcal · P \(p) g · G \(c) g · L \(f) g"
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
