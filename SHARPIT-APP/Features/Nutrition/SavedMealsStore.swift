import Foundation
import Observation

/// The athlete's saved meals (« Mes repas », SHARPIT ADR-071): a meal kept under a name, logged
/// whole in one tap from the add-food sheet. Deleting one never touches the days it was logged in.
@MainActor
@Observable
final class SavedMealsStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var meals: [V1SavedMeal] = []
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
            meals = try await client.savedMeals(token: try await tokenProvider())
            phase = .ready
        } catch is CancellationError {
        } catch {
            guard phase != .ready else { return }
            phase = .failed(SharpitErrorGuidance.message(for: error, subject: "Tes repas enregistrés"))
        }
    }

    /// Takes the meal off the list at once, and puts it back if the server refuses.
    func delete(_ meal: V1SavedMeal) async {
        guard let index = meals.firstIndex(where: { $0.id == meal.id }) else { return }
        meals.remove(at: index)
        failure = nil
        do {
            try await SharpitRetry.run {
                try await client.deleteSavedMeal(id: meal.id, token: try await tokenProvider())
            }
        } catch FoodLogError.notFound {
            // Already gone on the server: what the athlete asked for is true.
        } catch {
            meals.insert(meal, at: min(index, meals.count))
            failure = FoodLogStore.failureMessage(error, action: "Repas non supprimé")
        }
    }
}
