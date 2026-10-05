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

    let client: any FoodLogServing
    let tokenProvider: () async throws -> String
    private let onChange: @MainActor () async -> Void
    private let reportFailure: @MainActor (String) -> Void

    init(
        trainingDayId: String = TrainingDayId.today(now: .now),
        client: any FoodLogServing,
        tokenProvider: @escaping () async throws -> String,
        onChange: @escaping @MainActor () async -> Void = {},
        reportFailure: @escaping @MainActor (String) -> Void = { SharpitWriteFailures.shared.report($0) }
    ) {
        self.trainingDayId = trainingDayId
        self.client = client
        self.tokenProvider = tokenProvider
        self.onChange = onChange
        self.reportFailure = reportFailure
    }

    /// The four meals, always in the order a day is read, empty ones included.
    var sections: [MealSection] {
        FoodLogMeal.allCases.map { meal in
            MealSection(meal: meal, entries: entries.filter { $0.meal == meal })
        }
    }

    var hasEntries: Bool { !entries.isEmpty }

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
        } catch FoodLogError.notFound {
            // Already gone on the server: what the athlete asked for is true.
            await onChange()
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

    // MARK: Helpers

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
