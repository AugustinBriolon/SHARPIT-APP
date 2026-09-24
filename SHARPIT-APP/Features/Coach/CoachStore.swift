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

    /// Called when the server carried out an approved change, so Plan and Résumé reload.
    var onCalendarChanged: (() -> Void)?

    /// The answers already sent back, so a continuation that fails is not re-sent in a loop
    /// (the web's `lastStepApprovalResponseFingerprint`).
    private var sentApprovals: Set<String> = []

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

    /// Whether a coach proposal is waiting for the athlete's answer.
    var hasPendingApproval: Bool {
        messages.last?.parts?.contains { $0["state"]?.string == "approval-requested" } ?? false
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isReplying else { return }

        // A proposal left open is refused by the new question, as on the web.
        for index in messages.indices {
            if let parts = messages[index].parts {
                messages[index].parts = CoachUIParts.dismissingUnresolved(parts)
            }
        }
        let question = CoachMessage(role: .user, text: text, context: pendingContext)
        messages.append(question)
        draft = ""
        pendingContext = nil
        failure = nil

        // The placeholder is appended before the first chunk so the thread shows the coach has
        // started, rather than staying still until the first word lands.
        let answer = CoachMessage(role: .assistant, text: "", parts: [])
        let history = messages
        messages.append(answer)
        await stream(into: answer.id, history: history)
    }

    /// The athlete's answer to a proposal card. Once every proposal of the step has one, the
    /// turn goes back to the server, which carries out the approved ones and goes on writing in
    /// the same message — the web's `addToolApprovalResponse` and `sendAutomaticallyWhen`.
    func respond(to approvalId: String, approved: Bool) async {
        guard !isReplying, let index = messages.indices.last,
              messages[index].role == .assistant, let parts = messages[index].parts
        else { return }

        let answered = CoachUIParts.responding(parts, approvalId: approvalId, approved: approved)
        messages[index].parts = answered
        failure = nil

        guard CoachUIParts.isCompleteWithApprovalResponses(answered),
              let fingerprint = CoachUIParts.approvalFingerprint(answered),
              !sentApprovals.contains(fingerprint)
        else { return }
        sentApprovals.insert(fingerprint)
        await stream(into: messages[index].id, history: messages)
    }

    /// Streams the server's answer into the turn `id`, building its parts chunk by chunk.
    private func stream(into id: String, history: [CoachMessage]) async {
        isReplying = true
        defer { isReplying = false }

        guard let tokenProvider else {
            dropEmptyAnswer()
            failure = "Connecte-toi pour parler au coach."
            return
        }

        let appliedBefore = messages.first { $0.id == id }?.parts.map(CoachUIParts.appliedChanges) ?? 0
        do {
            let token = try await tokenProvider()
            var assembler = CoachUIMessageAssembler(parts: messages.first { $0.id == id }?.parts ?? [])

            for try await chunk in client.reply(to: history, token: token) {
                assembler.apply(chunk)
                guard let index = messages.firstIndex(where: { $0.id == id }) else { break }
                messages[index].parts = assembler.parts
                messages[index].text = assembler.text
            }

            // An answer that never arrived is not an answer; leaving the empty bubble would
            // read as the coach having nothing to say.
            if !CoachUIParts.hasContent(assembler.parts) {
                dropEmptyAnswer()
                failure = "Le coach n'a pas répondu. Réessaie."
            } else {
                await persist(token: token)
            }
            if CoachUIParts.appliedChanges(assembler.parts) > appliedBefore {
                onCalendarChanged?()
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
        sentApprovals = []
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
            sentApprovals = []
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
        if let last = messages.last, last.role == .assistant, !CoachUIParts.hasContent(last.parts ?? []),
           last.text.isEmpty {
            messages.removeLast()
        }
    }
}
