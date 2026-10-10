import Foundation

/// `/api/v1/coach/quota` — what is left of the athlete's coach budget over a rolling 24 h,
/// counted in questions by the web (SHARPIT ADR-077). Pro buys about ten times Free's.
nonisolated struct V1CoachQuota: Decodable, Equatable, Sendable {
    let isPro: Bool
    let dailyQuestions: Int
    let remainingQuestions: Int
    /// Share of the budget spent, 0 to 1.
    let usedRatio: Double
    /// Set once the budget is spent: seconds until enough of it frees up.
    let retryAfterSeconds: Int?
}

nonisolated protocol CoachQuotaServing: Sendable {
    func quota(token: String) async throws -> V1CoachQuota
}

actor CoachQuotaClient: CoachQuotaServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func quota(token: String) async throws -> V1CoachQuota {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/coach/quota"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
        return try JSONDecoder().decode(V1CoachQuota.self, from: data)
    }
}
