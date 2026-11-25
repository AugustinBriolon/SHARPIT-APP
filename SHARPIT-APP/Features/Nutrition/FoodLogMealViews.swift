import SwiftUI
import TipKit

/// Which meals the Nutrition page lists for a day.
nonisolated enum NutritionMealsMode: Equatable {
    /// The day's own log: the four meals, each with its « + », entries editable.
    case foodLog
    /// A day imported from MyFitnessPal: its meals, read-only.
    case imported
    /// The log not read yet: the four meals held in place, so the page never shows a partial
    /// list that changes under the finger once the log arrives.
    case loading

    static func resolve(foodLogReady: Bool, foodLogEntries: Int, importedMeals: Int) -> NutritionMealsMode {
        guard foodLogReady else { return .loading }
        // Only a day the athlete never logged in SharpIt can be an import (ADR-061).
        return foodLogEntries == 0 && importedMeals > 0 ? .imported : .foodLog
    }
}

/// The day's four meals, in order, each opening its page and with its own « + ».
struct FoodLogMealsSection: View {
    let store: FoodLogStore
    let flags: [NutritionEntryFlag]
    /// The log not read yet and none kept: the meals are named, only their value is awaited.
    var isLoading = false
    let onAdd: (FoodLogMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Repas")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            if !isLoading {
                TipView(CopyMealTip())
                    .tipBackground(SharpitColor.tile)
                    .tint(SharpitColor.foreground)
                    .padding(.vertical, SharpitSpacing.xs)
            }
            let sections = store.sections
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 { CliniqueDivider() }
                row(section)
            }
        }
    }

    @ViewBuilder
    private func row(_ section: FoodLogStore.MealSection) -> some View {
        if isLoading {
            FoodLogMealRow(section: section, flagged: false, isLoading: true)
        } else {
            loadedRow(section)
        }
    }

    private func loadedRow(_ section: FoodLogStore.MealSection) -> some View {
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

/// A meal's glyph before its name — sunrise, sun, moon, leaf — on the day's log and on an imported day.
struct NutritionMealGlyph: View {
    /// The meal's key (`breakfast`, `lunch`, `dinner`, `snacks`).
    let meal: String
    var isMuted = false

    var body: some View {
        Image(systemName: NutritionReadout.mealSymbol(meal))
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(isMuted ? SharpitColor.slate : SharpitColor.foreground)
            .frame(width: 24)
            .accessibilityHidden(true)
    }
}

/// A meal on a line: its name over its foods, its energy at the end — or « Ajouter » while empty.
private struct FoodLogMealRow: View {
    let section: FoodLogStore.MealSection
    let flagged: Bool
    var skipped = false
    /// The meal's value is on its way: its name stands, its energy alone is redacted.
    var isLoading = false

    /// A meal still being read is not shown as an empty one.
    private var isMuted: Bool { section.entries.isEmpty && !isLoading }

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            NutritionMealGlyph(meal: section.meal.storedName, isMuted: isMuted)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(section.meal.label)
                        .font(SharpitTypography.system(size: 15, weight: isMuted ? .regular : .semibold, relativeTo: .body))
                        .foregroundStyle(isMuted ? SharpitColor.slate : SharpitColor.foreground)
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
            if isLoading {
                Text(NutritionReadout.kcal(500))
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                    .redacted(reason: .placeholder)
                    .accessibilityLabel("Chargement")
            } else if section.entries.isEmpty {
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
    /// The named meals laid open onto their foods.
    @State private var openGroups: Set<String> = []
    @State private var deleting: FoodLogMealItem.Group?
    /// The named meal being kept in « Mes repas »; nil, the whole meal of the day.
    @State private var savingGroup: FoodLogMealItem.Group?

    var body: some View {
        let section = store.section(meal)
        List {
            Section {
                FoodPortionPreview(
                    nutrients: FoodPortion.Nutrients(kcal: section.kcal, protein: section.protein, carbs: section.carbs, fat: section.fat),
                    caption: FoodLogMealReadout.share(of: section.kcal, in: store.targets.kcal)
                )
            }
            .sharpitListRows()
            .listRowSeparator(.hidden)

            if let health = store.mealHealth(meal), health.score != nil || !health.highlights.isEmpty {
                MealHealthSection(health: health)
            }

            Section {
                ForEach(FoodLogMealItem.items(of: section.entries)) { item in
                    switch item {
                    case .entry(let entry):
                        entryRow(entry)
                    case .group(let group):
                        FoodLogGroupRow(group: group, isOpen: openGroups.contains(group.id)) {
                            SharpitMotion.run(SharpitMotion.reveal) { openGroups.formSymmetricDifference([group.id]) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !group.isPending {
                                SharpitSwipeDeleteButton { deleting = group }
                            }
                        }
                        .contextMenu {
                            if !group.isPending {
                                Button { nameMeal(group.label, group: group) } label: {
                                    Label("Enregistrer dans Mes repas", systemImage: "bookmark")
                                }
                                Button(role: .destructive) { deleting = group } label: {
                                    // On the athlete's iPhone the menu drew the bin in the app's ink
                                    // tint beside the red word: the glyph carries its own red.
                                    Label {
                                        Text("Supprimer")
                                    } icon: {
                                        Image(uiImage: UIImage(systemName: "trash")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal) ?? UIImage())
                                    }
                                }
                            }
                        }
                        if openGroups.contains(group.id) {
                            ForEach(group.entries) { entry in
                                entryRow(entry).padding(.leading, SharpitSpacing.md)
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
        .sharpitGroupedList(wash: .watch)
        .animation(SharpitMotion.selection, value: section.entries)
        .navigationTitle(meal.label)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            // The button alone, no dock around it; « Copier la veille » is in the « … » menu.
            SharpitBareActions {
                Button { addRequest = FoodAddRequest(meal: meal) } label: {
                    Text("Ajouter un aliment").frame(maxWidth: .infinity)
                }
                .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { Task { await store.copyFromPreviousDay(meal) } } label: {
                        Label("Copier le repas de la veille", systemImage: "doc.on.doc")
                    }
                    if !section.entries.isEmpty {
                        Button { nameMeal(SavedMealNaming.defaultName(section.entries), group: nil) } label: {
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
        .confirmationDialog(
            String(localized: "Supprimer « \(deleting?.label ?? "") » ?"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { group in
            Button(String(localized: "Supprimer le repas et ses \(group.entries.count) aliments"), role: .destructive) {
                Task { await store.deleteGroup(group.id) }
            }
        }
        .sheet(item: $addRequest) { FoodAddSheet(store: store, request: $0) }
        .sheet(item: $editing) { FoodEntryEditSheet(store: store, entry: $0) }
    }

    private func entryRow(_ entry: V1FoodLogEntry) -> some View {
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

    private func nameMeal(_ name: String, group: FoodLogMealItem.Group?) {
        mealName = String(name.prefix(80))
        savingGroup = group
        isNamingMeal = true
    }

    private func saveMeal() {
        let name = String(mealName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty else { return }
        let groupId = savingGroup?.id
        Task {
            if let saved = await store.saveMeal(meal, name: name, groupId: groupId) { savedName = saved.name }
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
                Text([entry.eatenMinute.map(FoodEatenTime.clock), FoodPortion.gramsLabel(entry.grams)].compactMap { $0 }.joined(separator: " · "))
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.slate)
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
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(NutritionReadout.kcal(entry.kcal))
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                    Text("kcal")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
                NutritionMacroSplitBar(entry: entry)
                    .frame(width: 120)
            }
        }
        .opacity(entry.isPending ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(entry.isPending ? "" : String(localized: "Modifie la quantité ou le repas"))
    }

}

/// What a meal's page lists: a food on its own, or the foods logged together as one named meal
/// (SHARPIT ADR-134) — the meal at the place of its first food. A meal down to one food is that food.
enum FoodLogMealItem: Identifiable, Equatable {
    struct Group: Identifiable, Equatable {
        let id: String
        let label: String
        let entries: [V1FoodLogEntry]

        var kcal: Double { entries.reduce(0) { $0 + $1.kcal } }
        var isPending: Bool { entries.contains(where: \.isPending) }
    }

    case entry(V1FoodLogEntry)
    case group(Group)

    var id: String {
        switch self {
        case .entry(let entry): entry.id
        case .group(let group): "group-\(group.id)"
        }
    }

    static func items(of entries: [V1FoodLogEntry]) -> [FoodLogMealItem] {
        let grouped = Dictionary(grouping: entries.filter { $0.groupId != nil && $0.groupLabel != nil }, by: { $0.groupId ?? "" })
        var seen: Set<String> = []
        return entries.compactMap { entry in
            guard let groupId = entry.groupId, let label = entry.groupLabel, let members = grouped[groupId], members.count > 1 else {
                return .entry(entry)
            }
            guard seen.insert(groupId).inserted else { return nil }
            return .group(Group(id: groupId, label: label, entries: members))
        }
    }
}

/// A named meal on its line: its name, how many foods, its energy, and the way to its foods.
private struct FoodLogGroupRow: View {
    let group: FoodLogMealItem.Group
    let isOpen: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(DescribedMealTotal.foodsCaption(group.entries.count))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(NutritionReadout.kcal(group.kcal))
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                    Text("kcal")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .opacity(group.isPending ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOpen ? String(localized: "Ouvert") : String(localized: "Fermé"))
    }
}

/// The words of a meal's page.
enum FoodLogMealReadout {
    /// « 31 % de ta journée »: the meal's energy against the day's target, nil without one.
    static func share(of kcal: Double, in target: Int?) -> String? {
        guard let target, target > 0, kcal > 0, let percent = Int(exactly: (kcal / Double(target) * 100).rounded()) else { return nil }
        return String(localized: "\(percent) % de ta journée")
    }
}
