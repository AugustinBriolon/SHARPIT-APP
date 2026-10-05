import SwiftUI

/// Which meals the Nutrition page lists for a day.
nonisolated enum NutritionMealsMode: Equatable {
    /// The day's own log: the four meals, each with its « + », entries editable.
    case foodLog
    /// A day imported from MyFitnessPal (or the log not read yet): its meals, read-only.
    case imported
    /// Nothing to list.
    case none

    static func resolve(foodLogReady: Bool, foodLogEntries: Int, importedMeals: Int) -> NutritionMealsMode {
        if foodLogReady && (foodLogEntries > 0 || importedMeals == 0) { return .foodLog }
        if importedMeals > 0 { return .imported }
        return foodLogEntries > 0 ? .foodLog : .none
    }
}

/// The day's four meals, in order, each opening its page and with its own « + ».
struct FoodLogMealsSection: View {
    let store: FoodLogStore
    let flags: [NutritionEntryFlag]
    let onAdd: (FoodLogMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(spacing: SharpitSpacing.xs) {
                SharpitEyebrow("Repas")
                Spacer(minLength: 0)
                if let day = store.dayHealth, day.score != nil {
                    Text("Note du jour")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    FoodHealthBadge(meal: day)
                }
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: 0) {
                let sections = store.sections
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    row(section)
                    if index < sections.count - 1 {
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

    private func row(_ section: FoodLogStore.MealSection) -> some View {
        HStack(spacing: 0) {
            if section.entries.isEmpty {
                Button { onAdd(section.meal) } label: {
                    FoodLogMealRow(section: section, health: nil, flagged: false, opensPage: false)
                }
                .buttonStyle(.sharpitPressable)
            } else {
                NavigationLink {
                    FoodLogMealPage(store: store, meal: section.meal, flags: flags)
                } label: {
                    FoodLogMealRow(
                        section: section, health: store.mealHealth(section.meal),
                        flagged: isFlagged(section), opensPage: true
                    )
                }
                .buttonStyle(.sharpitPressable)
            }
            Button { onAdd(section.meal) } label: {
                // A small mark, a full-size target: the circle is drawn at 28 pt, the tap is 44.
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(SharpitNutritionTone.mealLabel(section.meal.storedName))
                    .frame(width: 28, height: 28)
                    .background(SharpitNutritionTone.meal(section.meal.storedName).opacity(0.12), in: Circle())
                    .frame(width: SharpitSpacing.minimumTouchTarget, height: SharpitSpacing.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.sharpitPressable)
            .padding(.trailing, SharpitSpacing.sm)
            .accessibilityLabel("Ajouter un aliment au \(section.meal.label.lowercased())")
        }
        .contextMenu {
            Button { Task { await store.copyFromPreviousDay(section.meal) } } label: {
                Label("Copier le repas de la veille", systemImage: "doc.on.doc")
            }
        }
    }

    private func isFlagged(_ section: FoodLogStore.MealSection) -> Bool {
        flags.contains { flag in section.entries.contains { flag.matches(meal: section.meal, entry: $0.name) } }
    }
}

private struct FoodLogMealRow: View {
    let section: FoodLogStore.MealSection
    /// The meal's score (SHARPIT ADR-070), shown once the server scored these very entries.
    let health: V1MealHealth?
    let flagged: Bool
    let opensPage: Bool

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            ZStack {
                Circle().fill(SharpitNutritionTone.meal(section.meal.storedName).opacity(0.14)).frame(width: 32, height: 32)
                Image(systemName: NutritionReadout.mealSymbol(section.meal.storedName))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitNutritionTone.mealLabel(section.meal.storedName))
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.meal.label)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                HStack(spacing: 4) {
                    Text(countLabel)
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
            if let health, health.score != nil {
                FoodHealthBadge(meal: health)
            }
            if !section.entries.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(NutritionReadout.kcal(section.kcal))
                        .font(SharpitTypography.instrument)
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.numericText(value: section.kcal))
                    Text("kcal")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            if opensPage {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, SharpitSpacing.md)
        .padding(.trailing, SharpitSpacing.sm)
        .padding(.vertical, SharpitSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(opensPage ? "Ouvre le repas" : "Ajoute un aliment")
    }

    private var countLabel: String {
        switch section.entries.count {
        case 0: "Rien de noté"
        case 1: "1 aliment"
        default: "\(section.entries.count) aliments"
        }
    }
}

/// One meal of the day's log: its energy and macros, then each food — tapped to change its
/// weight or meal, swiped to take it out — and « + » to add another.
struct FoodLogMealPage: View {
    let store: FoodLogStore
    let meal: FoodLogMeal
    let flags: [NutritionEntryFlag]

    @State private var addRequest: FoodAddRequest?
    @State private var editing: V1FoodLogEntry?
    @State private var isNamingMeal = false
    @State private var mealName = ""
    /// The name the meal was kept under, said once at the foot of the page.
    @State private var savedName: String?

    var body: some View {
        let section = store.section(meal)
        List {
            Section {
                FoodPortionPreview(nutrients: FoodPortion.Nutrients(
                    kcal: section.kcal, protein: section.protein, carbs: section.carbs, fat: section.fat
                ))
            }
            .sharpitListRows()

            if let health = store.mealHealth(meal), health.score != nil || !health.highlights.isEmpty {
                MealHealthSection(health: health)
            }

            Section {
                if section.entries.isEmpty {
                    Button("Ajouter un aliment") { addRequest = FoodAddRequest(meal: meal) }
                        .foregroundStyle(SharpitNutritionTone.mealLabel(meal.storedName))
                }
                ForEach(section.entries) { entry in
                    Button { editing = entry } label: {
                        FoodLogEntryRow(entry: entry, flag: flags.first { $0.matches(meal: meal, entry: entry.name) })
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.isPending)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !entry.isPending {
                            Button(role: .destructive) {
                                Task { await store.delete(entry) }
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                SharpitEyebrow(countLabel(section.entries.count))
            } footer: {
                if let savedName {
                    SharpitListFooter("« \(savedName) » est dans Mes repas : tu peux le noter d'un geste depuis « + ».")
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .animation(SharpitMotion.selection, value: section.entries)
        .navigationTitle(meal.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addRequest = FoodAddRequest(meal: meal) } label: {
                    Label("Ajouter un aliment", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { Task { await store.copyFromPreviousDay(meal) } } label: {
                        Label("Copier le repas de la veille", systemImage: "doc.on.doc")
                    }
                    if !section.entries.isEmpty {
                        Button {
                            mealName = SavedMealNaming.defaultName(section.entries)
                            isNamingMeal = true
                        } label: {
                            Label("Enregistrer ce repas", systemImage: "bookmark")
                        }
                        .disabled(section.entries.contains(where: \.isPending))
                    }
                } label: {
                    Label("Plus", systemImage: "ellipsis")
                }
            }
        }
        .alert("Enregistrer ce repas", isPresented: $isNamingMeal) {
            TextField("Nom du repas", text: $mealName)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") { saveMeal() }
                .disabled(mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Il sera dans « Mes repas », à noter d'un geste un autre jour.")
        }
        .sheet(item: $addRequest) { FoodAddSheet(store: store, request: $0) }
        .sheet(item: $editing) { FoodEntryEditSheet(store: store, entry: $0) }
    }

    private func saveMeal() {
        let name = String(mealName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty else { return }
        Task {
            if let saved = await store.saveMeal(meal, name: name) { savedName = saved.name }
        }
    }

    private func countLabel(_ count: Int) -> String {
        switch count {
        case 0: "Rien de noté"
        case 1: "1 aliment"
        default: "\(count) aliments"
        }
    }
}

/// A logged food: its name, the weight and macros, its energy, and the coach's flag if any.
private struct FoodLogEntryRow: View {
    let entry: V1FoodLogEntry
    let flag: NutritionEntryFlag?

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.mutedForeground)
                NutritionMacroSplitBar(entry: entry)
                    .frame(maxWidth: 120)
                if let flag {
                    Label(flag.label, systemImage: "exclamationmark.circle.fill")
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(SharpitColor.signalCaution)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SharpitColor.signalCaution.opacity(0.12), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: SharpitSpacing.xs) {
                if entry.health != nil {
                    FoodHealthBadge(health: entry.health)
                }
                Text(NutritionReadout.kcal(entry.kcal))
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.foreground)
            }
        }
        .opacity(entry.isPending ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(entry.isPending ? "" : "Modifie la quantité ou le repas")
    }

    private var detail: String {
        let macros = "P \(Int(entry.protein.rounded())) · G \(Int(entry.carbs.rounded())) · L \(Int(entry.fat.rounded())) g"
        return "\(FoodPortion.gramsLabel(entry.grams)) · \(macros)"
    }
}
