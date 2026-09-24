import Foundation
import Observation

/// One coach conversation.
///
/// The context is a property of the *next* message, not of the conversation: the athlete
/// attaches a subject, sends, and the tag travels with that turn. Attaching a new one
/// later moves the topic, which is the web's rule (ADR-030).
@MainActor
@Observable
final class CoachStore {
    private(set) var messages: [CoachMessage] = []
    private(set) var isReplying = false
    private(set) var failure: String?
    /// The server's id for this conversation, once it has been saved. Nil for a new one.
    private(set) var conversationId: String?

    /// What the next message will carry. Set when the athlete arrives from another screen,
    /// and droppable before sending.
    var pendingContext: CoachDiscussContext?

    var draft = ""

    private let client: any CoachChatServing
    /// Nil where nothing is kept, in previews: the conversation then lives only on screen.
    private let conversations: (any CoachConversationServing)?
    private let tokenProvider: (() async throws -> String)?

    init(
        client: any CoachChatServing,
        conversations: (any CoachConversationServing)? = nil,
        tokenProvider: (() async throws -> String)?
    ) {
        self.client = client
        self.conversations = conversations
        self.tokenProvider = tokenProvider
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isReplying
    }

    var isEmpty: Bool { messages.isEmpty }

    func attach(_ context: CoachDiscussContext) {
        pendingContext = context
    }

    func dropContext() {
        pendingContext = nil
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isReplying else { return }

        let question = CoachMessage(role: .user, text: text, context: pendingContext)
        messages.append(question)
        draft = ""
        pendingContext = nil
        failure = nil
        isReplying = true
        defer { isReplying = false }

        guard let tokenProvider else {
            failure = "Connecte-toi pour parler au coach."
            return
        }

        do {
            let token = try await tokenProvider()
            // The placeholder is appended before the first delta so the thread shows the
            // coach has started, rather than staying still until the first word lands.
            let answer = CoachMessage(role: .assistant, text: "")
            messages.append(answer)

            for try await delta in client.reply(to: messages.dropLast(), token: token) {
                guard let index = messages.firstIndex(where: { $0.id == answer.id }) else { break }
                messages[index].text += delta
            }

            // An answer that never arrived is not an answer; leaving the empty bubble would
            // read as the coach having nothing to say.
            if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
                messages.removeLast()
                failure = "Le coach n'a pas répondu. Réessaie."
            } else {
                await persist(token: token)
            }
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .unauthorized {
            dropEmptyAnswer()
            failure = "Session expirée. Reconnecte-toi."
        } catch let error as CoachChatError {
            dropEmptyAnswer()
            failure = error.errorDescription
        } catch {
            dropEmptyAnswer()
            failure = "La réponse n'a pas abouti. Réessaie."
        }
    }

    /// Starts again from an empty thread. Refused while an answer is arriving, which would
    /// otherwise land in a conversation the athlete has already left.
    func startNewConversation() {
        guard !isReplying else { return }
        messages = []
        conversationId = nil
        pendingContext = nil
        draft = ""
        failure = nil
    }

    /// Replaces the thread with a saved conversation. True when it is open.
    @discardableResult
    func open(conversationId id: String) async -> Bool {
        guard !isReplying, let conversations, let tokenProvider else { return false }
        do {
            let conversation = try await conversations.conversation(id: id, token: try await tokenProvider())
            messages = conversation.messages
            conversationId = conversation.id
            pendingContext = nil
            draft = ""
            failure = nil
            return true
        } catch {
            failure = "Cette conversation n'a pas pu être ouverte."
            return false
        }
    }

    /// A conversation was deleted from history. If it is the one on screen, the thread goes
    /// with it — keeping it would leave the next answer saved into nothing.
    func forget(conversationId id: String) {
        guard conversationId == id else { return }
        startNewConversation()
    }

    /// Saves the whole thread after an answer, the way the web does: created on the first
    /// exchange, then replaced. A failure is not shown — the answer is on screen and the next
    /// one saves the whole thread again, so nothing is lost by waiting.
    private func persist(token: String) async {
        guard let conversations else { return }
        do {
            if let conversationId {
                try await conversations.save(id: conversationId, messages: messages, token: token)
            } else {
                conversationId = try await conversations.create(messages: messages, token: token)
            }
        } catch {}
    }

    private func dropEmptyAnswer() {
        if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
            messages.removeLast()
        }
    }
}
