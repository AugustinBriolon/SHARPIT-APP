import Foundation
import Observation

/// One training day of the in-app food log (SHARPIT ADR-061): its entries by meal, the
/// athlete's targets and the foods logged lately.
///
/// A write never makes the athlete wait: the change shows on the tap and goes out behind,
/// through `SharpitRetry`. One that fails for good is put back and said in the app's toast,
/// since the sheet it came from is closed by then. Every write the server takes rebuilds the
/// day there, so `onChange` reads `/api/v1/nutrition` again for the totals rather than adding
/// them up here.
@MainActor
@Observable
final class FoodLogStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// One meal of the day and what was logged in it, oldest first.
    struct MealSection: Equatable, Identifiable {
        let meal: FoodLogMeal
        let entries: [V1FoodLogEntry]

        var id: FoodLogMeal { meal }
        var kcal: Double { entries.reduce(0) { $0 + $1.kcal } }
        var protein: Double { entries.reduce(0) { $0 + $1.protein } }
        var carbs: Double { entries.reduce(0) { $0 + $1.carbs } }
        var fat: Double { entries.reduce(0) { $0 + $1.fat } }
    }

    private(set) var phase: Phase = .loading
    private(set) var trainingDayId: String
    private(set) var entries: [V1FoodLogEntry] = []
    private(set) var targets: V1NutritionTargets = .none
    private(set) var recent: [V1FoodLogRecentFood] = []
    /// The server's score of each meal and of the day (SHARPIT ADR-070), read with the entries.
    private(set) var health: V1FoodLogDayHealth?
    /// The entries each meal's score was computed on: a meal changed since shows no score until
    /// the server scored it again, never a stale one.
    private var healthBasis: [FoodLogMeal: [String]] = [:]

    let client: any FoodLogServing
    let tokenProvider: () async throws -> String
    private let onChange: @MainActor () async -> Void
    private let reportFailure: @MainActor (String) -> Void
    /// When Apple Santé is linked and nutrition write is allowed, mirror day totals.
    private let healthWriter: (any HealthWriting)?

    init(
        trainingDayId: String = TrainingDayId.today(now: .now),
        client: any FoodLogServing,
        tokenProvider: @escaping () async throws -> String,
        onChange: @escaping @MainActor () async -> Void = {},
        reportFailure: @escaping @MainActor (String) -> Void = { SharpitWriteFailures.shared.report($0) },
        healthWriter: (any HealthWriting)? = nil
    ) {
        self.trainingDayId = trainingDayId
        self.client = client
        self.tokenProvider = tokenProvider
        self.onChange = onChange
        self.reportFailure = reportFailure
        self.healthWriter = healthWriter
    }

    /// The four meals, always in the order a day is read, empty ones included.
    var sections: [MealSection] {
        FoodLogMeal.allCases.map { meal in
            MealSection(meal: meal, entries: entries.filter { $0.meal == meal })
        }
    }

    var hasEntries: Bool { !entries.isEmpty }

    /// A meal's score, when its entries are still the ones the server scored.
    func mealHealth(_ meal: FoodLogMeal) -> V1MealHealth? {
        guard healthBasis[meal] == Self.basis(of: entries, meal: meal) else { return nil }
        return health?.meal(meal)
    }

    /// The day's score, when no meal changed since the server scored it.
    var dayHealth: V1MealHealth? {
        let current = FoodLogMeal.allCases.allSatisfy { healthBasis[$0] == Self.basis(of: entries, meal: $0) }
        return current ? health?.day : nil
    }

    func section(_ meal: FoodLogMeal) -> MealSection {
        MealSection(meal: meal, entries: entries.filter { $0.meal == meal })
    }

    /// The weight last logged of a food, for the portion picker's presets.
    func lastGrams(of product: V1FoodProduct) -> Double? {
        recent.first { $0.product.id == product.id }?.lastGrams
    }

    /// Reads a day. Another day than the one held clears the entries first, so a day never
    /// shows under another date.
    func load(trainingDayId dayId: String) async {
        if dayId != trainingDayId {
            trainingDayId = dayId
            entries = []
            phase = .loading
        }
        do {
            let day = try await client.day(trainingDayId: dayId, token: try await tokenProvider())
            guard dayId == trainingDayId else { return }
            entries = day.entries
            targets = day.targets
            recent = day.recent
            adoptHealth(day)
            phase = .ready
        } catch is CancellationError {
        } catch {
            guard dayId == trainingDayId, phase != .ready else { return }
            phase = .failed(SharpitErrorGuidance.message(for: error, subject: "Ton journal alimentaire"))
        }
    }

    // MARK: Writes

    /// Shows the entry at once with its nutrients worked out here, then swaps it for the
    /// server's once it is stored.
    func add(_ draft: FoodLogDraft) async {
        let pending = Self.pendingEntry(for: draft)
        entries.append(pending)
        do {
            let stored = try await SharpitRetry.run {
                try await client.add(draft, token: try await tokenProvider())
            }
            replace(pending.id, with: Self.keepingHealth(of: pending, in: stored))
            rememberRecent(draft, stored: stored)
            await onChange()
            await refreshHealth()
            await mirrorNutritionToAppleHealth()
        } catch {
            entries.removeAll { $0.id == pending.id }
            reportFailure(Self.failureMessage(error, action: "Aliment non ajouté"))
        }
    }

    func update(_ entry: V1FoodLogEntry, _ change: FoodLogEntryChange) async {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let original = entries[index]
        entries[index] = Self.applying(change, to: original)
        do {
            let stored = try await SharpitRetry.run {
                try await client.update(entryId: entry.id, change, token: try await tokenProvider())
            }
            replace(entry.id, with: Self.keepingHealth(of: original, in: stored))
            await onChange()
            await refreshHealth()
            await mirrorNutritionToAppleHealth()
        } catch {
            replace(entry.id, with: original)
            reportFailure(Self.failureMessage(error, action: "Modification non enregistrée"))
        }
    }

    func delete(_ entry: V1FoodLogEntry) async {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries.remove(at: index)
        do {
            try await SharpitRetry.run {
                try await client.delete(entryId: entry.id, token: try await tokenProvider())
            }
            await onChange()
            await refreshHealth()
            await mirrorNutritionToAppleHealth()
        } catch FoodLogError.notFound {
            // Already gone on the server: what the athlete asked for is true.
            await onChange()
            await refreshHealth()
            await mirrorNutritionToAppleHealth()
        } catch {
            entries.insert(entry, at: min(index, entries.count))
            reportFailure(Self.failureMessage(error, action: "Aliment non supprimé"))
        }
    }

    func setTargets(_ newTargets: V1NutritionTargets) async {
        let previous = targets
        targets = newTargets
        do {
            targets = try await SharpitRetry.run {
                try await client.setTargets(newTargets, trainingDayId: trainingDayId, token: try await tokenProvider())
            }
            await onChange()
        } catch {
            targets = previous
            reportFailure(Self.failureMessage(error, action: "Objectifs non enregistrés"))
        }
    }

    /// An own food edited from the sheet: the recent list picks it with its new values.
    func productChanged(_ product: V1FoodProduct) {
        recent = recent.map { $0.product.id == product.id ? V1FoodLogRecentFood(product: product, lastGrams: $0.lastGrams) : $0 }
    }

    /// An own food deleted: it can no longer be picked. Entries logged with it stay.
    func productDeleted(_ product: V1FoodProduct) {
        recent.removeAll { $0.product.id == product.id }
    }

    // MARK: Copy and saved meals (SHARPIT ADR-071)

    /// Logs the same meal of the day before — or, without a meal, the whole day — into this day.
    /// The day before is not held here, so the rows arrive with the server's answer; an empty
    /// source is said rather than doing nothing.
    func copyFromPreviousDay(_ meal: FoodLogMeal?) async {
        guard let from = TrainingDayId.previous(trainingDayId) else { return }
        let dayId = trainingDayId
        do {
            let copied = try await SharpitRetry.run {
                try await client.copy(from: from, meal: meal, to: dayId, token: try await tokenProvider())
            }
            guard dayId == trainingDayId else { return }
            guard !copied.isEmpty else {
                reportFailure(meal == nil ? "Rien de noté la veille : rien à copier." : "Ce repas était vide la veille : rien à copier.")
                return
            }
            entries.append(contentsOf: copied)
            await onChange()
            await refreshHealth()
            await mirrorNutritionToAppleHealth()
        } catch {
            reportFailure(Self.failureMessage(error, action: "Repas non copié"))
        }
    }

    /// Shows the saved foods in the meal at once, then swaps them for the server's entries.
    func logSavedMeal(_ saved: V1SavedMeal, into meal: FoodLogMeal) async {
        let pending = Self.pendingEntries(for: saved, meal: meal)
        entries.append(contentsOf: pending)
        let pendingIds = Set(pending.map(\.id))
        let dayId = trainingDayId
        do {
            let stored = try await SharpitRetry.run {
                try await client.logSavedMeal(id: saved.id, trainingDayId: dayId, meal: meal, token: try await tokenProvider())
            }
            entries.removeAll { pendingIds.contains($0.id) }
            guard dayId == trainingDayId else { return }
            entries.append(contentsOf: stored)
            await onChange()
            await refreshHealth()
            await mirrorNutritionToAppleHealth()
        } catch {
            entries.removeAll { pendingIds.contains($0.id) }
            reportFailure(Self.failureMessage(error, action: "Repas non ajouté"))
        }
    }

    /// Keeps a meal of this day under a name. It needs the server's answer to be listed, so the
    /// caller learns whether it was kept; a failure is said in the toast.
    func saveMeal(_ meal: FoodLogMeal, name: String) async -> V1SavedMeal? {
        let dayId = trainingDayId
        do {
            return try await SharpitRetry.run {
                try await client.saveMeal(name: name, trainingDayId: dayId, meal: meal, token: try await tokenProvider())
            }
        } catch {
            reportFailure(Self.failureMessage(error, action: "Repas non enregistré"))
            return nil
        }
    }

    nonisolated static func pendingEntries(for saved: V1SavedMeal, meal: FoodLogMeal) -> [V1FoodLogEntry] {
        saved.items.map { item in
            V1FoodLogEntry(
                id: "pending-\(UUID().uuidString)", meal: meal, productId: item.productId, name: item.name,
                brand: item.brand, grams: item.grams, kcal: item.kcal, protein: item.protein,
                carbs: item.carbs, fat: item.fat, fiber: item.fiber, sugar: item.sugar, createdAt: nil
            )
        }
    }

    // MARK: Helpers

    /// Mirrors the day's totals into Apple Santé when write access was granted. Failures stay quiet.
    private func mirrorNutritionToAppleHealth() async {
        guard let healthWriter else { return }
        let day = trainingDayId
        let kcal = entries.reduce(0.0) { $0 + $1.kcal }
        let protein = entries.reduce(0.0) { $0 + $1.protein }
        let carbs = entries.reduce(0.0) { $0 + $1.carbs }
        let fat = entries.reduce(0.0) { $0 + $1.fat }
        try? await healthWriter.saveNutritionDay(
            day: day,
            kcal: kcal,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat
        )
    }

    private func adoptHealth(_ day: V1FoodLogDay) {
        health = day.health
        healthBasis = Dictionary(uniqueKeysWithValues: FoodLogMeal.allCases.map {
            ($0, Self.basis(of: day.entries, meal: $0))
        })
    }

    /// Reads the day again for its scores once a write landed. The entries stay as shown: the
    /// score only shows where they match what the server scored.
    private func refreshHealth() async {
        guard !entries.contains(where: \.isPending) else { return }
        let dayId = trainingDayId
        guard let day = try? await client.day(trainingDayId: dayId, token: try await tokenProvider()),
              dayId == trainingDayId
        else { return }
        adoptHealth(day)
    }

    nonisolated static func basis(of entries: [V1FoodLogEntry], meal: FoodLogMeal) -> [String] {
        entries.filter { $0.meal == meal }.map { "\($0.id):\($0.grams)" }.sorted()
    }

    private func replace(_ id: String, with entry: V1FoodLogEntry) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index] = entry
    }

    private func rememberRecent(_ draft: FoodLogDraft, stored: V1FoodLogEntry) {
        guard case .product(let product) = draft.source else { return }
        recent.removeAll { $0.product.id == product.id }
        recent.insert(V1FoodLogRecentFood(product: product, lastGrams: stored.grams), at: 0)
    }

    nonisolated static func pendingEntry(for draft: FoodLogDraft) -> V1FoodLogEntry {
        let id = "pending-\(UUID().uuidString)"
        switch draft.source {
        case .product(let product):
            let portion = FoodPortion.nutrients(of: product, grams: draft.grams)
            return V1FoodLogEntry(
                id: id, meal: draft.meal, productId: product.id, name: product.name, brand: product.brand,
                grams: draft.grams, kcal: portion.kcal, protein: portion.protein, carbs: portion.carbs, fat: portion.fat,
                health: product.health
            )
        case .quick(let quick):
            return V1FoodLogEntry(
                id: id, meal: draft.meal, productId: nil, name: quick.name, brand: nil, grams: draft.grams,
                kcal: quick.kcal, protein: quick.protein ?? 0, carbs: quick.carbs ?? 0, fat: quick.fat ?? 0
            )
        }
    }

    /// The server's echo, with the score the row already showed when the echo carries none: a
    /// portion changes the grams, never the food's quality.
    nonisolated static func keepingHealth(of shown: V1FoodLogEntry, in stored: V1FoodLogEntry) -> V1FoodLogEntry {
        guard stored.health == nil, stored.productId == shown.productId else { return stored }
        var kept = stored
        kept.health = shown.health
        return kept
    }

    nonisolated static func applying(_ change: FoodLogEntryChange, to entry: V1FoodLogEntry) -> V1FoodLogEntry {
        var updated = entry
        if let grams = change.grams, grams != entry.grams {
            let portion = FoodPortion.nutrients(of: entry, grams: grams)
            updated.grams = grams
            updated.kcal = portion.kcal
            updated.protein = portion.protein
            updated.carbs = portion.carbs
            updated.fat = portion.fat
        }
        if let meal = change.meal { updated.meal = meal }
        return updated
    }

    nonisolated static func failureMessage(_ error: Error, action: String) -> String {
        switch error {
        case let error as SharpitAPIError where error == .unauthorized:
            "\(action) : ta session a expiré."
        case let error as SharpitAPIError where error == .transport:
            "\(action) : pas de connexion internet."
        case FoodLogError.notFound:
            "\(action) : cet aliment n'existe plus."
        default:
            "\(action). Réessaie dans un instant."
        }
    }
}

nonisolated extension V1FoodLogEntry {
    init(
        id: String, meal: FoodLogMeal, productId: String?, name: String, brand: String?, grams: Double,
        kcal: Double, protein: Double, carbs: Double, fat: Double
    ) {
        self.init(
            id: id, meal: meal, productId: productId, name: name, brand: brand, grams: grams,
            kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: nil, sugar: nil, createdAt: nil
        )
    }

    /// Shown before the server answered: the row reads as on its way.
    var isPending: Bool { id.hasPrefix("pending-") }
}
