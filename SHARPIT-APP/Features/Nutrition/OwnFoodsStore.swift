import Foundation
import Observation

/// The athlete's own foods (« Mes aliments »), to pick, edit or delete from the add-food sheet.
/// An edit or a delete never touches what was already logged: entries keep their snapshot.
@MainActor
@Observable
final class OwnFoodsStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var foods: [V1FoodProduct] = []
    /// A delete that failed, said on the page the athlete is still on.
    private(set) var failure: String?

    private let client: any FoodLogServing
    private let tokenProvider: () async throws -> String

    init(client: any FoodLogServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func load() async {
        do {
            let loaded = try await client.ownFoods(token: try await tokenProvider())
            foods = Self.sorted(loaded)
            phase = .ready
        } catch is CancellationError {
        } catch {
            guard phase != .ready else { return }
            phase = .failed(SharpitErrorGuidance.message(for: error, subject: "La liste de tes aliments"))
        }
    }

    /// Waits for the server's answer (retried): the edit page closes on success only.
    func update(_ product: V1FoodProduct, with draft: FoodCustomDraft) async throws -> V1FoodProduct {
        let stored = try await SharpitRetry.run {
            try await client.updateCustomFood(id: product.id, draft, token: try await tokenProvider())
        }
        foods = Self.sorted(foods.map { $0.id == stored.id ? stored : $0 })
        return stored
    }

    /// Takes the food off the list at once, and puts it back if the server refuses.
    func delete(_ product: V1FoodProduct) async -> Bool {
        guard let index = foods.firstIndex(where: { $0.id == product.id }) else { return false }
        foods.remove(at: index)
        failure = nil
        do {
            try await SharpitRetry.run {
                try await client.deleteCustomFood(id: product.id, token: try await tokenProvider())
            }
            return true
        } catch FoodLogError.notFound {
            // Already gone on the server: what the athlete asked for is true.
            return true
        } catch {
            foods.insert(product, at: min(index, foods.count))
            failure = FoodLogStore.failureMessage(error, action: "Aliment non supprimé")
            return false
        }
    }

    /// A new food created from the sheet shows in the list without a reload.
    func add(_ product: V1FoodProduct) {
        guard product.source == "CUSTOM", !foods.contains(where: { $0.id == product.id }) else { return }
        foods = Self.sorted(foods + [product])
    }

    nonisolated static func sorted(_ foods: [V1FoodProduct]) -> [V1FoodProduct] {
        foods.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

nonisolated extension FoodCustomDraft {
    /// An own food as its edit form opens on.
    init(product: V1FoodProduct) {
        self.init(
            name: product.name,
            brand: product.brand,
            kcalPer100g: product.kcalPer100g,
            proteinPer100g: product.proteinPer100g,
            carbsPer100g: product.carbsPer100g,
            fatPer100g: product.fatPer100g,
            fiberPer100g: product.fiberPer100g,
            sugarPer100g: product.sugarPer100g,
            saltPer100g: product.saltPer100g,
            saturatedFatPer100g: product.saturatedFatPer100g,
            servingGrams: product.servingGrams
        )
    }
}
