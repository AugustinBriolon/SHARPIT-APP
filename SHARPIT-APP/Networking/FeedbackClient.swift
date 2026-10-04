import Foundation

/// A note written through « Donner un avis », as `/api/v1/feedback` takes it.
nonisolated struct V1FeedbackNote: Codable, Sendable, Equatable {
    let message: String
    /// Where it was written from: `settings`…
    let context: String
    /// « 1.0 (202610041900) ».
    let appVersion: String
}

nonisolated protocol FeedbackServing: Sendable {
    func sendFeedback(_ note: V1FeedbackNote, token: String) async throws
}

actor FeedbackClient: FeedbackServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func sendFeedback(_ note: V1FeedbackNote, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/feedback"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(note)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        try Self.check(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    /// 201 is kept; a 400 carries the server's words, retried no more than any refusal.
    static func check(status: Int, body: Data) throws {
        switch status {
        case 200, 201: return
        case 401: throw SharpitAPIError.unauthorized
        case 429: throw SharpitAPIError.rateLimited
        case 400..<500:
            let message = (try? JSONDecoder().decode([String: String].self, from: body))?["error"]
            throw message.map(SharpitAPIError.message) ?? SharpitAPIError.badRequest
        default: throw SharpitAPIError.server
        }
    }
}
