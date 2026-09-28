import Foundation

/// The week's figures behind a review — the web's `WeeklyStats`, the fields the app shows.
nonisolated struct V1WeeklyStats: Codable, Equatable, Sendable {
    struct Sleep: Codable, Equatable, Sendable {
        var avgDurationMin: Double?
        var avgScore: Double?
    }

    struct Recovery: Codable, Equatable, Sendable {
        var avgReadiness: Double?
        var avgHrv: Double?
    }

    struct SportShare: Codable, Equatable, Sendable {
        let type: String
        let count: Int
        let durationMin: Double
    }

    var weekStart: String?
    var weekEnd: String?
    /// Monday → Sunday; nil on a day without data, never 0.
    var dailyLoad: [Double?]?
    var dailySleepScore: [Double?]?
    var byType: [SportShare]?
    var sessionsDone: Int?
    var sessionsPlanned: Int?
    var totalLoad: Double?
    var totalDurationMin: Double?
    var prevTotalLoad: Double?
    var sleep: Sleep?
    var recovery: Recovery?
}

/// The coach's review of one week: markdown written by the coach, and the figures it read.
nonisolated struct V1WeeklyReview: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let weekStart: String
    let content: String
    var stats: V1WeeklyStats?
    let generatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, weekStart, content, stats, generatedAt
    }

    init(id: String, weekStart: String, content: String, stats: V1WeeklyStats? = nil, generatedAt: Date? = nil) {
        self.id = id
        self.weekStart = weekStart
        self.content = content
        self.stats = stats
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        weekStart = String((try container.decode(String.self, forKey: .weekStart)).prefix(10))
        content = try container.decode(String.self, forKey: .content)
        stats = try? container.decodeIfPresent(V1WeeklyStats.self, forKey: .stats)
        generatedAt = (try? container.decodeIfPresent(String.self, forKey: .generatedAt))
            .flatMap { try? Date($0, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
    }
}

enum WeeklyReviewError: Error, Equatable {
    /// The review is a SharpIt Pro analysis; the server says so with a 403.
    case proRequired
}

nonisolated protocol WeeklyReviewServing: Sendable {
    /// The latest review written, or nil when none exists yet.
    func latestReview(token: String) async throws -> V1WeeklyReview?
    /// Writes the review of the week in progress.
    func generateReview(token: String) async throws -> V1WeeklyReview
}

/// `/api/v1/coach/weekly-review` — the web's handler (ADR-040), Pro-gated server-side.
actor WeeklyReviewClient: WeeklyReviewServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    private nonisolated struct Envelope: Decodable {
        let review: V1WeeklyReview?
    }

    func latestReview(token: String) async throws -> V1WeeklyReview? {
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/coach/weekly-review"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "latest", value: "1")]
        guard let url = components?.url else { throw SharpitAPIError.server }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request).review
    }

    func generateReview(token: String) async throws -> V1WeeklyReview {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/coach/weekly-review"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 90
        guard let review = try await send(request).review else { throw SharpitAPIError.server }
        return review
    }

    private func send(_ request: URLRequest) async throws -> Envelope {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return try JSONDecoder().decode(Envelope.self, from: data)
        case 401: throw SharpitAPIError.unauthorized
        case 403: throw WeeklyReviewError.proRequired
        case 429: throw SharpitAPIError.rateLimited
        default: throw SharpitAPIError.server
        }
    }
}
