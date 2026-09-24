import Foundation
import OSLog

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
    /// The turn exactly as the server stored it, for a conversation opened from history.
    /// Saving sends this back rather than the text alone, so parts the app cannot show — the
    /// web's tool calls, say — survive a save from the phone.
    let stored: JSONValue?

    init(
        id: String = UUID().uuidString,
        role: Role,
        text: String,
        context: CoachDiscussContext? = nil,
        stored: JSONValue? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.context = context
        self.stored = stored
    }

    /// Reads a stored UI message. Nil for a turn the app has no place for (a system message,
    /// say), which is left out of the thread rather than shown wrong.
    init?(stored: JSONValue) {
        guard let id = stored["id"]?.string,
              let role = stored["role"]?.string.flatMap(Role.init(rawValue:))
        else { return nil }

        let text = (stored["parts"]?.array ?? [])
            .filter { $0["type"]?.string == "text" }
            .compactMap { $0["text"]?.string }
            .joined(separator: "\n\n")

        self.init(
            id: id,
            role: role,
            text: text,
            context: role == .user ? stored["metadata"].flatMap(CoachDiscussContext.init(storedMetadata:)) : nil,
            stored: stored
        )
    }
}

/// Why a coach answer ended without text, in words the athlete can act on.
nonisolated enum CoachChatError: Error, Equatable, LocalizedError {
    /// The route opened its stream, then reported a failure inside it — a model or gateway
    /// error arrives this way, with a 200 status the HTTP check cannot catch.
    case streamFailed(String)
    /// The coach proposed a change to the calendar and waits for it to be approved, which the
    /// app cannot do yet (Lot B).
    case awaitsApproval
    /// A refusal the route answered before streaming: consent, rate limit, AI budget.
    case refused(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .streamFailed(let text): text
        case .awaitsApproval: "Le coach propose une modification du calendrier. Valide-la sur le web pour l'instant."
        case .refused(let status, let message):
            message ?? (status == 429 ? "Trop de messages d'affilée. Réessaie dans un instant." : "Le coach est indisponible (\(status)).")
        }
    }
}

/// One event of the UI-message stream, as far as the app reads it.
nonisolated enum CoachStreamEvent: Equatable {
    case text(String)
    case error(String)
    case approvalRequest
    case other(String)
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
    nonisolated private static let log = Logger(subsystem: "app.sharpit.ios", category: "coach")
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
            guard (200..<300).contains(http.statusCode) else {
                var body = Data()
                for try await byte in bytes.prefix(4096) { body.append(byte) }
                let message = Self.errorMessage(inBody: body)
                Self.log.error("coach chat refused: \(http.statusCode) \(String(decoding: body, as: UTF8.self), privacy: .public)")
                throw CoachChatError.refused(status: http.statusCode, message: message)
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var sawText = false
                    var sawApproval = false
                    var kinds: [String] = []
                    for try await line in bytes.lines {
                        guard let event = Self.event(inEventLine: line) else { continue }
                        switch event {
                        case .text(let delta):
                            sawText = true
                            continuation.yield(delta)
                        case .error(let text):
                            Self.log.error("coach stream error: \(text, privacy: .public)")
                            throw CoachChatError.streamFailed(text)
                        case .approvalRequest:
                            sawApproval = true
                        case .other(let kind):
                            if kinds.last != kind { kinds.append(kind) }
                        }
                    }
                    if !sawText {
                        Self.log.error("coach stream ended without text; events: \(kinds.joined(separator: ","), privacy: .public)")
                        if sawApproval { throw CoachChatError.awaitsApproval }
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
            wire["metadata"] = context.metadata.mapValues(\.foundationObject)
        }
        return wire
    }

    /// Pulls the text out of one SSE line, or nil when the line carries anything else.
    nonisolated static func textDelta(inEventLine line: String) -> String? {
        guard case .text(let delta) = event(inEventLine: line) else { return nil }
        return delta
    }

    /// Reads one SSE line. Nil for anything that is not a JSON event (blank lines, `[DONE]`).
    nonisolated static func event(inEventLine line: String) -> CoachStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }

        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String
        else { return nil }

        switch type {
        case "text-delta":
            // `delta` is the v5 field; `textDelta` was its name before. Reading both costs one
            // line and spares a silent blank screen if the server is a version behind.
            guard let delta = event["delta"] as? String ?? event["textDelta"] as? String else { return nil }
            return .text(delta)
        case "error":
            // The AI SDK masks server details as "An error occurred." unless the route says more.
            let text = event["errorText"] as? String ?? ""
            return .error(text.isEmpty || text == "An error occurred." ? "Le coach a rencontré une erreur. Réessaie." : text)
        case "tool-approval-request":
            return .approvalRequest
        default:
            return .other(type)
        }
    }

    /// The `error` (or `message`) a JSON refusal carries, if any.
    nonisolated static func errorMessage(inBody body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return (json["error"] as? String) ?? (json["message"] as? String)
    }
}
