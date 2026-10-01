import Foundation

/// Why a food-log call failed beyond the shared `SharpitAPIError` causes.
nonisolated enum FoodLogError: Error, Equatable, LocalizedError {
    /// The entry or the food is gone (deleted elsewhere, or never this athlete's).
    case notFound
    /// Open Food Facts did not answer the server.
    case openFoodFactsUnavailable

    var errorDescription: String? {
        switch self {
        case .notFound: "Cet aliment n'existe plus."
        case .openFoodFactsUnavailable: "Open Food Facts ne répond pas. Réessaie dans un instant."
        }
    }
}

/// The in-app food log: the day's entries, the foods to pick from and the athlete's targets.
nonisolated protocol FoodLogServing: Sendable {
    func day(trainingDayId: String, token: String) async throws -> V1FoodLogDay
    func add(_ draft: FoodLogDraft, token: String) async throws -> V1FoodLogEntry
    func update(entryId: String, _ change: FoodLogEntryChange, token: String) async throws -> V1FoodLogEntry
    func delete(entryId: String, token: String) async throws
    func search(_ query: String, token: String) async throws -> V1FoodSearchResults
    /// Nil when Open Food Facts does not know the code.
    func product(barcode: String, token: String) async throws -> V1FoodProduct?
    func createCustomFood(_ draft: FoodCustomDraft, token: String) async throws -> V1FoodProduct
    func setTargets(_ targets: V1NutritionTargets, trainingDayId: String, token: String) async throws -> V1NutritionTargets
}

actor FoodLogClient: FoodLogServing {
    private nonisolated static let path = "/api/v1/food-log"

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func day(trainingDayId: String, token: String) async throws -> V1FoodLogDay {
        let request = try request(
            Self.path, method: "GET", query: [URLQueryItem(name: "trainingDayId", value: trainingDayId)], token: token
        )
        return try decode(V1FoodLogDay.self, from: try await send(request))
    }

    func add(_ draft: FoodLogDraft, token: String) async throws -> V1FoodLogEntry {
        var request = try request(Self.path, method: "POST", token: token)
        request.httpBody = try Self.body(for: draft)
        return try decode(V1FoodLogEntryEnvelope.self, from: try await send(request)).entry
    }

    func update(entryId: String, _ change: FoodLogEntryChange, token: String) async throws -> V1FoodLogEntry {
        var request = try request("\(Self.path)/\(entryId)", method: "PATCH", token: token)
        request.httpBody = try Self.body(for: change)
        return try decode(V1FoodLogEntryEnvelope.self, from: try await send(request)).entry
    }

    func delete(entryId: String, token: String) async throws {
        _ = try await send(try request("\(Self.path)/\(entryId)", method: "DELETE", token: token))
    }

    func search(_ query: String, token: String) async throws -> V1FoodSearchResults {
        let request = try request(
            "\(Self.path)/foods", method: "GET", query: [URLQueryItem(name: "q", value: query)], token: token
        )
        return try decode(V1FoodSearchResults.self, from: try await send(request))
    }

    func product(barcode: String, token: String) async throws -> V1FoodProduct? {
        let request = try request("\(Self.path)/foods/barcode/\(barcode)", method: "GET", token: token)
        do {
            return try decode(V1FoodProductEnvelope.self, from: try await send(request)).product
        } catch FoodLogError.notFound {
            return nil
        }
    }

    func createCustomFood(_ draft: FoodCustomDraft, token: String) async throws -> V1FoodProduct {
        var request = try request("\(Self.path)/foods", method: "POST", token: token)
        request.httpBody = try Self.body(for: draft)
        return try decode(V1FoodProductEnvelope.self, from: try await send(request)).product
    }

    func setTargets(_ targets: V1NutritionTargets, trainingDayId: String, token: String) async throws -> V1NutritionTargets {
        var request = try request(
            "\(Self.path)/targets", method: "PUT", query: [URLQueryItem(name: "trainingDayId", value: trainingDayId)], token: token
        )
        request.httpBody = try Self.body(for: targets)
        return try decode(V1NutritionTargetsEnvelope.self, from: try await send(request)).targets
    }

    // MARK: Bodies

    /// Exactly one of `productId` and `quick`, as the server requires.
    nonisolated static func body(for draft: FoodLogDraft) throws -> Data {
        var payload: [String: Any] = [
            "trainingDayId": draft.trainingDayId,
            "meal": draft.meal.rawValue,
            "grams": draft.grams,
        ]
        switch draft.source {
        case .product(let product):
            payload["productId"] = product.id
        case .quick(let quick):
            payload["quick"] = [
                "name": quick.name,
                "kcal": quick.kcal,
                "protein": quick.protein ?? 0,
                "carbs": quick.carbs ?? 0,
                "fat": quick.fat ?? 0,
            ] as [String: Any]
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Only the fields that change: an absent key leaves the server's value.
    nonisolated static func body(for change: FoodLogEntryChange) throws -> Data {
        var payload: [String: Any] = [:]
        if let grams = change.grams { payload["grams"] = grams }
        if let meal = change.meal { payload["meal"] = meal.rawValue }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Nil optional values go out as JSON null: the server stores them as "not given".
    nonisolated static func body(for draft: FoodCustomDraft) throws -> Data {
        let payload: [String: Any] = [
            "name": draft.name,
            "brand": draft.brand ?? NSNull(),
            "kcalPer100g": draft.kcalPer100g,
            "proteinPer100g": draft.proteinPer100g,
            "carbsPer100g": draft.carbsPer100g,
            "fatPer100g": draft.fatPer100g,
            "fiberPer100g": draft.fiberPer100g ?? NSNull(),
            "sugarPer100g": draft.sugarPer100g ?? NSNull(),
            "servingGrams": draft.servingGrams ?? NSNull(),
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Every target is sent, nil as JSON null, so a cleared field clears on the server.
    nonisolated static func body(for targets: V1NutritionTargets) throws -> Data {
        let payload: [String: Any] = [
            "kcal": targets.kcal ?? NSNull(),
            "proteinG": targets.proteinG ?? NSNull(),
            "carbsG": targets.carbsG ?? NSNull(),
            "fatG": targets.fatG ?? NSNull(),
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: Transport

    private func request(_ path: String, method: String, query: [URLQueryItem] = [], token: String) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw SharpitAPIError.server
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw SharpitAPIError.server }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" && method != "DELETE" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        try Self.check(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        return data
    }

    nonisolated static func check(status: Int) throws {
        switch status {
        case 200...299: return
        case 400: throw SharpitAPIError.badRequest
        case 401, 403: throw SharpitAPIError.unauthorized
        case 404: throw FoodLogError.notFound
        case 429: throw SharpitAPIError.rateLimited
        case 503: throw FoodLogError.openFoodFactsUnavailable
        default: throw SharpitAPIError.server
        }
    }

    private func decode<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws -> Payload {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SharpitAPIError.server
        }
    }
}
