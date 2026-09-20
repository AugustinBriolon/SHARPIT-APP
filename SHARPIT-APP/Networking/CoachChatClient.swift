import Foundation

/// One turn of a coach conversation.
nonisolated struct CoachMessage: Identifiable, Sendable, Equatable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let id: String
    let role: Role
    var text: String
    /// What the athlete had attached when they sent this. Only ever on a user turn.
    var context: CoachDiscussContext?

    init(id: String = UUID().uuidString, role: Role, text: String, context: CoachDiscussContext? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.context = context
    }
}

protocol CoachChatServing: Sendable {
    /// Streams the coach's answer, one delta at a time.
    func reply(to messages: [CoachMessage], token: String) -> AsyncThrowingStream<String, Error>
}

/// Talks to `/api/coach/chat`.
///
/// The route answers with the AI SDK's UI-message stream: server-sent events whose data is
/// a JSON envelope tagged by `type`. Only the text deltas are consumed here; every other
/// event — tool calls, step boundaries, metadata — is skipped rather than rejected, so a
/// new event type on the server does not break an installed app.
actor CoachChatClient: CoachChatServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    nonisolated func reply(
        to messages: [CoachMessage],
        token: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await delta in try await self.stream(messages: messages, token: token) {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(
        messages: [CoachMessage],
        token: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        var request = URLRequest(url: baseURL.appending(path: "/api/coach/chat"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["messages": messages.map(Self.wireMessage)]
        )

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw SharpitAPIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw SharpitAPIError.server }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard let delta = Self.textDelta(inEventLine: line) else { continue }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The shape the route reads: a UI message with text parts, and the discuss context as
    /// metadata rather than as prose injected into the question.
    nonisolated static func wireMessage(_ message: CoachMessage) -> [String: Any] {
        var wire: [String: Any] = [
            "id": message.id,
            "role": message.role.rawValue,
            "parts": [["type": "text", "text": message.text]],
        ]
        if let context = message.context {
            wire["metadata"] = context.metadata
        }
        return wire
    }

    /// Pulls the text out of one SSE line, or nil when the line carries anything else.
    nonisolated static func textDelta(inEventLine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }

        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["type"] as? String == "text-delta"
        else { return nil }

        // `delta` is the v5 field; `textDelta` was its name before. Reading both costs one
        // line and spares a silent blank screen if the server is a version behind.
        return event["delta"] as? String ?? event["textDelta"] as? String
    }
}
