import Foundation
import Observation

/// Finds a food to log: typed (debounced, the athlete's own foods first, then Open Food Facts)
/// or scanned. The device never talks to Open Food Facts itself — the server does (ADR-061).
@MainActor
@Observable
final class FoodSearchStore {
    /// What a scanned code turned out to be.
    enum BarcodeOutcome: Equatable {
        case found(V1FoodProduct)
        /// Open Food Facts does not know it: the athlete types it in or creates the food.
        case unknown
        case failed(String)
    }

    static let minimumLength = 2
    static let maximumLength = 80

    private(set) var results: V1FoodSearchResults?
    private(set) var isSearching = false
    private(set) var failure: String?

    private let client: any FoodLogServing
    private let tokenProvider: () async throws -> String
    private let debounce: Duration
    private var pendingSearch: Task<Void, Never>?
    private var currentQuery = ""

    init(
        client: any FoodLogServing,
        tokenProvider: @escaping () async throws -> String,
        debounce: Duration = .milliseconds(350)
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.debounce = debounce
    }

    /// Whether the query is long enough to be searched; shorter, the recent foods show instead.
    static func isSearchable(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumLength
    }

    /// Searches once typing pauses. A query too short clears the results.
    func setQuery(_ text: String) {
        pendingSearch?.cancel()
        let query = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumLength))
        currentQuery = query
        guard query.count >= Self.minimumLength else {
            results = nil
            failure = nil
            isSearching = false
            return
        }
        isSearching = true
        pendingSearch = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.search(query)
        }
    }

    /// Waits for the search under way, if any — for tests and for a pull to refresh.
    func settle() async {
        await pendingSearch?.value
    }

    func lookUp(barcode: String) async -> BarcodeOutcome {
        do {
            let product = try await SharpitRetry.run {
                try await client.product(barcode: barcode, token: try await tokenProvider())
            }
            return product.map(BarcodeOutcome.found) ?? .unknown
        } catch FoodLogError.notFound {
            return .unknown
        } catch {
            return .failed(Self.message(for: error))
        }
    }

    private func search(_ query: String) async {
        do {
            let found = try await client.search(query, token: try await tokenProvider())
            guard query == currentQuery, !Task.isCancelled else { return }
            results = found
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            guard query == currentQuery else { return }
            failure = Self.message(for: error)
        }
        isSearching = false
    }

    static func message(for error: Error) -> String {
        switch error {
        case let error as SharpitAPIError where error == .rateLimited:
            "Trop de recherches d'affilée. Réessaie dans une minute."
        case let error as SharpitAPIError where error == .transport || error == .unauthorized:
            SharpitErrorGuidance.message(for: error, subject: "La recherche")
        case FoodLogError.openFoodFactsUnavailable:
            FoodLogError.openFoodFactsUnavailable.errorDescription ?? ""
        default:
            "La recherche n'a pas abouti. Réessaie dans un instant."
        }
    }
}
