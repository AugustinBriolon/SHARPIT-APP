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
        VStack(alignment: .leading, spacing: 0) {
            Text("Repas")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            let sections = store.sections
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 { CliniqueDivider() }
                row(section)
            }
        }
    }

    private func row(_ section: FoodLogStore.MealSection) -> some View {
        Group {
            if section.entries.isEmpty {
                Button { onAdd(section.meal) } label: {
                    FoodLogMealRow(section: section, flagged: false, skipped: store.isSkipped(section.meal))
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Ajoute un aliment")
            } else {
                NavigationLink {
                    FoodLogMealPage(store: store, meal: section.meal, flags: flags)
                } label: {
                    FoodLogMealRow(section: section, flagged: isFlagged(section))
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Ouvre le repas")
            }
        }
        .contextMenu {
            Button { Task { await store.copyFromPreviousDay(section.meal) } } label: {
                Label("Copier le repas de la veille", systemImage: "doc.on.doc")
            }
            if section.entries.isEmpty {
                skipButton(section.meal)
            }
        }
        .accessibilityActions {
            if section.entries.isEmpty { skipButton(section.meal) }
        }
    }

    /// A meal skipped on purpose is a choice the coach's reading respects, not a gap (SHARPIT ADR-113).
    @ViewBuilder
    private func skipButton(_ meal: FoodLogMeal) -> some View {
        if store.isSkipped(meal) {
            Button { Task { await store.setSkipped(meal, false) } } label: {
                Label("Annuler « repas sauté »", systemImage: "arrow.uturn.backward")
            }
        } else {
            Button { Task { await store.setSkipped(meal, true) } } label: {
                Label("J'ai sauté ce repas", systemImage: "fork.knife.circle")
            }
        }
    }

    private func isFlagged(_ section: FoodLogStore.MealSection) -> Bool {
        flags.contains { flag in section.entries.contains { flag.matches(meal: section.meal, entry: $0.name) } }
    }
}

/// A meal on a line: its name over its foods, its energy at the end — or « Ajouter » while empty.
private struct FoodLogMealRow: View {
    let section: FoodLogStore.MealSection
    let flagged: Bool
    var skipped = false

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(section.meal.label)
                        .font(SharpitTypography.system(size: 15, weight: section.entries.isEmpty ? .regular : .semibold, relativeTo: .body))
                        .foregroundStyle(section.entries.isEmpty ? SharpitColor.slate : SharpitColor.foreground)
                    if flagged {
                        CliniqueStatusPill(String(localized: "Signalé"), status: .watch)
                            .accessibilityLabel("Aliment signalé par le coach")
                    }
                }
                if !section.entries.isEmpty {
                    Text(NutritionReadout.mealLine(section.entries.map(\.name)))
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(1)
                } else if skipped {
                    Text("Repas sauté")
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            Spacer(minLength: SharpitSpacing.sm)
            if section.entries.isEmpty {
                Text("Ajouter")
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
            } else {
                Text(NutritionReadout.kcal(section.kcal))
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText(value: section.kcal))
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
                            SharpitSwipeDeleteButton {
                                Task { await store.delete(entry) }
                            }
                        }
                    }
                }
            } header: {
                SharpitEyebrow(countLabel(section.entries.count))
            } footer: {
                if let savedName {
                    SharpitListFooter(String(localized: "« \(savedName) » est dans Mes repas : tu peux le noter d'un geste depuis « + »."))
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
        case 0: String(localized: "Rien de noté")
        case 1: String(localized: "1 aliment")
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
                    .foregroundStyle(SharpitColor.slate)
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
        .accessibilityHint(entry.isPending ? "" : String(localized: "Modifie la quantité ou le repas"))
    }

    private var detail: String {
        let macros = "P \(Int(entry.protein.rounded())) · G \(Int(entry.carbs.rounded())) · L \(Int(entry.fat.rounded())) g"
        return "\(FoodPortion.gramsLabel(entry.grams)) · \(macros)"
    }
}
