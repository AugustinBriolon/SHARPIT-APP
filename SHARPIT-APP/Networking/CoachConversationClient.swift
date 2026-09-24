import Foundation

/// A past conversation, as the history lists it.
nonisolated struct CoachConversationSummary: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, updatedAt
    }

    init(id: String, title: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        updatedAt = try Date.fromAPI(container.decode(String.self, forKey: .updatedAt))
    }
}

/// A conversation opened from history.
nonisolated struct CoachConversation: Sendable, Equatable {
    let id: String
    let messages: [CoachMessage]
}

protocol CoachConversationServing: Sendable {
    func conversations(token: String) async throws -> [CoachConversationSummary]
    func conversation(id: String, token: String) async throws -> CoachConversation
    /// Creates the conversation from its first turns and returns its id.
    func create(messages: [CoachMessage], token: String) async throws -> String
    /// Replaces the whole history, the way the web saves it.
    func save(id: String, messages: [CoachMessage], token: String) async throws
    func delete(id: String, token: String) async throws
}

/// Talks to `/api/coach/conversations`.
///
/// The server keeps the history; the client saves it whole after each answer, as the web does.
actor CoachConversationClient: CoachConversationServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func conversations(token: String) async throws -> [CoachConversationSummary] {
        let data = try await send("GET", path: "/api/v1/coach/conversations", token: token)
        return try decode([CoachConversationSummary].self, from: data)
    }

    func conversation(id: String, token: String) async throws -> CoachConversation {
        let data = try await send("GET", path: "/api/v1/coach/conversations/\(id)", token: token)
        let stored = try decode(StoredConversation.self, from: data)
        return CoachConversation(
            id: stored.id,
            messages: (stored.messages.array ?? []).compactMap(CoachMessage.init(stored:))
        )
    }

    func create(messages: [CoachMessage], token: String) async throws -> String {
        let data = try await send(
            "POST",
            path: "/api/v1/coach/conversations",
            body: Self.body(for: messages),
            token: token
        )
        return try decode(StoredConversation.self, from: data).id
    }

    func save(id: String, messages: [CoachMessage], token: String) async throws {
        _ = try await send(
            "PUT",
            path: "/api/v1/coach/conversations/\(id)",
            body: Self.body(for: messages),
            token: token
        )
    }

    func delete(id: String, token: String) async throws {
        _ = try await send("DELETE", path: "/api/v1/coach/conversations/\(id)", token: token)
    }

    /// A turn read from history goes back as it came; one written here goes as the chat
    /// route reads it.
    nonisolated static func body(for messages: [CoachMessage]) throws -> Data {
        let wire: [Any] = messages.map { $0.stored?.foundationObject ?? CoachChatClient.wireMessage($0) }
        return try JSONSerialization.data(withJSONObject: ["messages": wire])
    }

    private struct StoredConversation: Decodable {
        let id: String
        let messages: JSONValue

        enum CodingKeys: String, CodingKey { case id, messages }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            messages = try container.decodeIfPresent(JSONValue.self, forKey: .messages) ?? .array([])
        }
    }

    private func send(_ method: String, path: String, body: Data? = nil, token: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 401: throw SharpitAPIError.unauthorized
        default: throw SharpitAPIError.server
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SharpitAPIError.server
        }
    }
}
