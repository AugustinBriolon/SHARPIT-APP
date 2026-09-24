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
    /// A coach turn's UI-message parts — its text, and the tool calls whose proposals the
    /// athlete approves or refuses (`CoachUIMessageAssembler`). Nil on the athlete's turns.
    var parts: [JSONValue]?

    init(
        id: String = UUID().uuidString,
        role: Role,
        text: String,
        context: CoachDiscussContext? = nil,
        stored: JSONValue? = nil,
        parts: [JSONValue]? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.context = context
        self.stored = stored
        self.parts = parts
    }

    /// Reads a stored UI message. Nil for a turn the app has no place for (a system message,
    /// say), which is left out of the thread rather than shown wrong.
    init?(stored: JSONValue) {
        guard let id = stored["id"]?.string,
              let role = stored["role"]?.string.flatMap(Role.init(rawValue:))
        else { return nil }

        let parts = stored["parts"]?.array ?? []

        self.init(
            id: id,
            role: role,
            text: CoachUIParts.text(in: parts),
            context: role == .user ? stored["metadata"].flatMap(CoachDiscussContext.init(storedMetadata:)) : nil,
            stored: stored,
            parts: role == .assistant ? parts : nil
        )
    }
}

/// Why a coach answer ended without text, in words the athlete can act on.
nonisolated enum CoachChatError: Error, Equatable, LocalizedError {
    /// The route opened its stream, then reported a failure inside it — a model or gateway
    /// error arrives this way, with a 200 status the HTTP check cannot catch.
    case streamFailed(String)
    /// A refusal the route answered before streaming: consent, rate limit, AI budget.
    case refused(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .streamFailed(let text): text
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
    /// Streams the coach's answer as the route's UI-message chunks, for
    /// `CoachUIMessageAssembler`. An `error` chunk ends the stream as `CoachChatError`.
    func reply(to messages: [CoachMessage], token: String) -> AsyncThrowingStream<JSONValue, Error>
}

/// Talks to `/api/coach/chat`.
///
/// The route answers with the AI SDK's UI-message stream: server-sent events whose data is
/// a JSON envelope tagged by `type`. Every chunk is handed on — text, reasoning, tool calls
/// and their approvals — so the turn can be rebuilt as the web has it; a chunk type the
/// assembler does not know is ignored there rather than rejected, so a new one on the server
/// does not break an installed app.
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
    ) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in try await self.stream(messages: messages, token: token) {
                        continuation.yield(chunk)
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
    ) async throws -> AsyncThrowingStream<JSONValue, Error> {
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
                    var kinds: [String] = []
                    for try await line in bytes.lines {
                        guard let chunk = Self.chunk(inEventLine: line) else { continue }
                        if case .error(let text) = Self.event(from: chunk) {
                            Self.log.error("coach stream error: \(text, privacy: .public)")
                            throw CoachChatError.streamFailed(text)
                        }
                        if let kind = chunk["type"]?.string, kinds.last != kind { kinds.append(kind) }
                        continuation.yield(chunk)
                    }
                    Self.log.debug("coach stream: \(kinds.joined(separator: ","), privacy: .public)")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The shape the route reads: a UI message with text parts, and the discuss context as
    /// metadata rather than as prose injected into the question. A coach turn goes back with
    /// every part it was built from — tool calls, approvals, provider metadata — and a turn
    /// read from history as it was stored, with its parts brought up to date.
    nonisolated static func wireMessage(_ message: CoachMessage) -> [String: Any] {
        if let parts = message.parts {
            var wire: [String: JSONValue]
            if case .object(let stored) = message.stored { wire = stored } else { wire = [:] }
            wire["id"] = wire["id"] ?? .string(message.id)
            wire["role"] = .string(message.role.rawValue)
            wire["parts"] = .array(parts)
            return JSONValue.object(wire).foundationObject as? [String: Any] ?? [:]
        }
        if let stored = message.stored, let wire = stored.foundationObject as? [String: Any] {
            return wire
        }
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

    /// Reads one SSE line as a chunk. Nil for anything else (blank lines, `[DONE]`).
    nonisolated static func chunk(inEventLine line: String) -> JSONValue? {
        guard line.hasPrefix("data:") else { return nil }

        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", !payload.isEmpty,
              let chunk = try? JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8)),
              chunk["type"]?.string != nil
        else { return nil }
        return chunk
    }

    /// Reads one SSE line. Nil for anything that is not a JSON event (blank lines, `[DONE]`).
    nonisolated static func event(inEventLine line: String) -> CoachStreamEvent? {
        chunk(inEventLine: line).flatMap(event(from:))
    }

    nonisolated static func event(from chunk: JSONValue) -> CoachStreamEvent? {
        guard let type = chunk["type"]?.string else { return nil }

        switch type {
        case "text-delta":
            // `delta` is the v5 field; `textDelta` was its name before. Reading both costs one
            // line and spares a silent blank screen if the server is a version behind.
            guard let delta = chunk["delta"]?.string ?? chunk["textDelta"]?.string else { return nil }
            return .text(delta)
        case "error":
            // The AI SDK masks server details as "An error occurred." unless the route says more.
            let text = chunk["errorText"]?.string ?? ""
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
