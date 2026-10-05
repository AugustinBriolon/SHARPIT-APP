import SwiftUI

// MARK: - Own foods

/// « Mes aliments »: the athlete's own foods. Adding to a meal, a tap picks one; from Paramètres,
/// with nothing to pick for, a tap edits it. A swipe edits it or deletes it, after asking.
/// Nothing already logged changes either way.
struct OwnFoodsPage: View {
    let store: OwnFoodsStore
    /// Nil where there is no meal to add to: the tap edits instead.
    var onPick: ((V1FoodProduct) -> Void)?
    let onEdit: (V1FoodProduct) -> Void
    let onCreate: () -> Void
    var onDeleted: (V1FoodProduct) -> Void = { _ in }

    @State private var pendingDelete: V1FoodProduct?

    var body: some View {
        List {
            switch store.phase {
            case .loading where store.foods.isEmpty:
                Section {
                    HStack(spacing: SharpitSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Chargement…").foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .sharpitListRows()
            case .failed(let message) where store.foods.isEmpty:
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SharpitColor.signalCaution)
                    Button("Réessayer") { Task { await store.load() } }
                }
                .sharpitListRows()
            default:
                if store.foods.isEmpty {
                    emptyState
                } else {
                    foodsSection
                }
            }
        }
        .sharpitGroupedList()
        .navigationTitle("Mes aliments")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
        .confirmationDialog(
            pendingDelete.map { "Supprimer « \($0.name) » ?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { product in
            Button("Supprimer l'aliment", role: .destructive) { delete(product) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Tes repas déjà notés gardent leurs valeurs.")
        }
    }

    private var foodsSection: some View {
        Section {
            ForEach(store.foods) { product in
                Button { (onPick ?? onEdit)(product) } label: {
                    FoodProductRow(product: product)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { pendingDelete = product } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                    Button { onEdit(product) } label: {
                        Label("Modifier", systemImage: "pencil")
                    }
                    .tint(SharpitColor.primary)
                }
                .contextMenu {
                    Button { onEdit(product) } label: { Label("Modifier", systemImage: "pencil") }
                    Button(role: .destructive) { pendingDelete = product } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
        } footer: {
            if let failure = store.failure {
                SharpitListFooter(failure, tone: SharpitColor.signalRisk)
            } else {
                SharpitListFooter(onPick == nil
                    ? "Touche un aliment pour le modifier, glisse vers la gauche pour le supprimer."
                    : "Glisse vers la gauche pour modifier ou supprimer un aliment.")
            }
        }
        .sharpitListRows()
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                Text("Aucun aliment à toi pour l'instant")
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text("Crée un aliment avec son étiquette : il apparaîtra ici et en tête de tes recherches.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, SharpitSpacing.xxs)
            Button(action: onCreate) {
                Label("Créer un aliment", systemImage: "plus.square.on.square")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
            }
        }
        .sharpitListRows()
    }

    private func delete(_ product: V1FoodProduct) {
        Task {
            if await store.delete(product) {
                onDeleted(product)
            }
        }
    }
}

// MARK: - Custom food

/// The athlete's own food, per 100 g: created, or one of theirs edited. It needs the server's
/// answer before going on (the id to log it, or the values to show), so the save waits for it
/// (retried), then hands the stored food on.
struct FoodCustomPage: View {
    enum Purpose {
        case create(name: String)
        case edit(V1FoodProduct)
    }

    let purpose: Purpose
    /// What creating does next: « Créer et ajouter » from a meal, « Créer » from Paramètres.
    let createTitle: String
    let save: (FoodCustomDraft) async throws -> V1FoodProduct
    let onSaved: (V1FoodProduct) -> Void

    @State private var name: String
    @State private var brand: String
    @State private var kcal: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var fiber: String
    @State private var sugar: String
    @State private var salt: String
    @State private var saturatedFat: String
    @State private var serving: String
    @State private var isSaving = false
    @State private var failure: String?

    init(
        purpose: Purpose,
        createTitle: String = "Créer et ajouter",
        save: @escaping (FoodCustomDraft) async throws -> V1FoodProduct,
        onSaved: @escaping (V1FoodProduct) -> Void
    ) {
        self.purpose = purpose
        self.createTitle = createTitle
        self.save = save
        self.onSaved = onSaved
        let field = { (value: Double?) in value.map(FoodPortion.editableFigure) ?? "" }
        switch purpose {
        case .create(let name):
            _name = State(initialValue: name.trimmingCharacters(in: .whitespacesAndNewlines))
            _brand = State(initialValue: "")
            _kcal = State(initialValue: "")
            _protein = State(initialValue: "")
            _carbs = State(initialValue: "")
            _fat = State(initialValue: "")
            _fiber = State(initialValue: "")
            _sugar = State(initialValue: "")
            _salt = State(initialValue: "")
            _saturatedFat = State(initialValue: "")
            _serving = State(initialValue: "")
        case .edit(let product):
            _name = State(initialValue: product.name)
            _brand = State(initialValue: product.brand ?? "")
            _kcal = State(initialValue: field(product.kcalPer100g))
            _protein = State(initialValue: field(product.proteinPer100g))
            _carbs = State(initialValue: field(product.carbsPer100g))
            _fat = State(initialValue: field(product.fatPer100g))
            _fiber = State(initialValue: field(product.fiberPer100g))
            _sugar = State(initialValue: field(product.sugarPer100g))
            _salt = State(initialValue: field(product.saltPer100g))
            _saturatedFat = State(initialValue: field(product.saturatedFatPer100g))
            _serving = State(initialValue: field(product.servingGrams))
        }
    }

    private var isEditing: Bool {
        if case .edit = purpose { return true }
        return false
    }

    private var draft: FoodCustomDraft? {
        FoodCustomForm.draft(
            name: name, brand: brand, kcal: kcal, protein: protein, carbs: carbs, fat: fat,
            fiber: fiber, sugar: sugar, salt: salt, saturatedFat: saturatedFat, serving: serving
        )
    }

    /// Editing, « Enregistrer » waits for a change: an untouched form has nothing to send.
    private var canSave: Bool {
        guard let draft, !isSaving else { return false }
        if case .edit(let product) = purpose { return draft != FoodCustomDraft(product: product) }
        return true
    }

    var body: some View {
        List {
            Section(eyebrow: "Aliment") {
                TextField("Nom", text: $name)
                    .textInputAutocapitalization(.sentences)
                TextField("Marque (optionnel)", text: $brand)
            }
            .sharpitListRows()

            Section(eyebrow: "Pour 100 g", footer: "Recopie l'étiquette. Fibres, sucres, sel et gras saturés sont optionnels ; avec les trois derniers, le score Sharpit lit tout l'aliment.") {
                FoodNumberRow(title: "Énergie", unit: "kcal", text: $kcal)
                FoodNumberRow(title: "Protéines", unit: "g", text: $protein)
                FoodNumberRow(title: "Glucides", unit: "g", text: $carbs)
                FoodNumberRow(title: "Lipides", unit: "g", text: $fat)
                FoodNumberRow(title: "Fibres", unit: "g", placeholder: "—", text: $fiber)
                FoodNumberRow(title: "Sucres", unit: "g", placeholder: "—", text: $sugar)
                FoodNumberRow(title: "Sel", unit: "g", placeholder: "—", text: $salt)
                FoodNumberRow(title: "Gras saturés", unit: "g", placeholder: "—", text: $saturatedFat)
            }
            .sharpitListRows()

            if case .edit(let product) = purpose, let health = product.health, health.coverage != .none {
                FoodHealthSections(health: health)
            }

            Section {
                FoodNumberRow(title: "Une portion", unit: "g", placeholder: "—", text: $serving)
            } header: {
                SharpitEyebrow("Portion")
            } footer: {
                SharpitListFooter(isEditing
                    ? "Optionnel : le poids d'une portion habituelle, proposé à l'ajout. Tes repas déjà notés gardent leurs valeurs."
                    : "Optionnel : le poids d'une portion habituelle, proposé à l'ajout.")
            }
            .sharpitListRows()

            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SharpitColor.signalCaution)
                }
                .sharpitListRows()
            }
        }
        .sharpitGroupedList()
        .safeAreaInset(edge: .bottom) {
            SharpitActionDock {
                SharpitPrimaryButton(title: isEditing ? "Enregistrer" : createTitle, isBusy: isSaving) {
                    Task { await submit() }
                }
                .disabled(!canSave)
            }
        }
        .navigationTitle(isEditing ? "Modifier l'aliment" : "Créer un aliment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        guard let draft else { return }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            let product = try await save(draft)
            onSaved(product)
        } catch {
            failure = FoodLogStore.failureMessage(error, action: isEditing ? "Aliment non modifié" : "Aliment non créé")
        }
    }
}

/// Paramètres › Mes aliments: the athlete's own foods kept on their own, with no meal to add to —
/// a tap edits, « + » creates, a swipe deletes. The list and both forms are the add-food sheet's.
struct OwnFoodsSettingsView: View {
    @State private var store: OwnFoodsStore
    @State private var editing: V1FoodProduct?
    @State private var isCreating = false
    private let client: any FoodLogServing
    private let tokenProvider: () async throws -> String

    init(client: any FoodLogServing = FoodLogClient(), tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
        _store = State(initialValue: OwnFoodsStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        OwnFoodsPage(
            store: store,
            onEdit: { editing = $0 },
            onCreate: { isCreating = true }
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isCreating = true } label: {
                    Label("Créer un aliment", systemImage: "plus")
                }
            }
        }
        // Not values on the settings path: that path is typed to its own routes.
        .navigationDestination(item: $editing) { product in
            FoodCustomPage(purpose: .edit(product)) { draft in
                try await store.update(product, with: draft)
            } onSaved: { _ in
                editing = nil
            }
        }
        .navigationDestination(isPresented: $isCreating) {
            FoodCustomPage(purpose: .create(name: ""), createTitle: "Créer") { draft in
                try await SharpitRetry.run {
                    try await client.createCustomFood(draft, token: try await tokenProvider())
                }
            } onSaved: { product in
                store.add(product)
                isCreating = false
            }
        }
    }
}
