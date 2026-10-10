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
    /// Bumped when the thread should jump to its end — opening history. The view scrolls; the
    /// store only signals.
    private(set) var endAnchorRevision = 0

    /// What the next message will carry. Set when the athlete arrives from another screen,
    /// and droppable before sending.
    var pendingContext: CoachDiscussContext?

    var draft = ""

    /// What is left of the coach budget, read on open and after each answer. Nil until read,
    /// and kept as it was when a read fails.
    private(set) var quota: V1CoachQuota?

    /// Called when the server carried out an approved change, so Plan and Résumé reload.
    var onCalendarChanged: (() -> Void)?

    /// The answers already sent back, so a continuation that fails is not re-sent in a loop
    /// (the web's `lastStepApprovalResponseFingerprint`).
    private var sentApprovals: Set<String> = []

    private let client: any CoachChatServing
    /// Nil where nothing is kept, in previews: the conversation then lives only on screen.
    private let conversations: (any CoachConversationServing)?
    private let tokenProvider: (() async throws -> String)?
    private let quotaClient: (any CoachQuotaServing)?
    /// The in-flight SSE consume task — cancelled by the stop control on the composer.
    private var replyTask: Task<Void, Never>?
    /// True only when the athlete pressed stop — not when Approve cancels a winding-down stream.
    private var userStoppedReply = false

    init(
        client: any CoachChatServing,
        conversations: (any CoachConversationServing)? = nil,
        quota: (any CoachQuotaServing)? = nil,
        tokenProvider: (() async throws -> String)?
    ) {
        self.client = client
        self.conversations = conversations
        self.quotaClient = quota
        self.tokenProvider = tokenProvider
    }

    func refreshQuota() async {
        guard let quotaClient, let tokenProvider else { return }
        if let fresh = try? await quotaClient.quota(token: try await tokenProvider()) {
            quota = fresh
        }
    }

    /// Cuts the live coach stream and the server request. Keeps any partial bubble already shown.
    func stopReply() {
        userStoppedReply = true
        replyTask?.cancel()
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
        userStoppedReply = false

        // The placeholder is appended before the first chunk so the thread shows the coach has
        // started, rather than staying still until the first word lands.
        let answer = CoachMessage(role: .assistant, text: "", parts: [])
        let history = messages
        messages.append(answer)
        await runStream(into: answer.id, turn: question, history: history)
    }

    /// The athlete's answer to a proposal card. Once every proposal of the step has one, the
    /// turn goes back to the server, which carries out the approved ones and goes on writing in
    /// the same message — the web's `addToolApprovalResponse` and `sendAutomaticallyWhen`.
    /// `replacingInput` updates the tool input before approval (edited meal / grams on logFoods).
    func respond(to approvalId: String, approved: Bool, replacingInput: JSONValue? = nil) async {
        await waitForReplyStop()
        guard !isReplying, let index = messages.indices.last,
              messages[index].role == .assistant, let parts = messages[index].parts
        else { return }

        let answered = CoachUIParts.responding(
            parts,
            approvalId: approvalId,
            approved: approved,
            replacingInput: replacingInput
        )
        messages[index].parts = answered
        failure = nil

        guard CoachUIParts.isCompleteWithApprovalResponses(answered),
              let fingerprint = CoachUIParts.approvalFingerprint(answered),
              !sentApprovals.contains(fingerprint)
        else { return }
        sentApprovals.insert(fingerprint)
        await runStream(into: messages[index].id, turn: messages[index], history: messages)
    }

    /// Re-sends a failed approval. `sentApprovals` would otherwise ignore the same fingerprint.
    /// Pair with the web's toolCallId idempotency — merge this after that SHARPIT-WEBAPP PR.
    func retry(approvalId: String, replacingInput: JSONValue? = nil) async {
        await waitForReplyStop()
        guard !isReplying, let index = messages.indices.last,
              messages[index].role == .assistant, let parts = messages[index].parts
        else { return }

        messages[index].parts = CoachUIParts.reopening(parts, approvalId: approvalId)
        clearSentApproval(containing: approvalId)
        await respond(to: approvalId, approved: true, replacingInput: replacingInput)
    }

    /// Owns the stream task so the composer stop control can cancel it.
    private func runStream(into id: String, turn: CoachMessage, history: [CoachMessage]) async {
        let task = Task { await stream(into: id, turn: turn, history: history) }
        replyTask = task
        await task.value
        if replyTask == task { replyTask = nil }
        await refreshQuota()
    }

    /// Cancels an in-flight reply and waits until `isReplying` clears — so Approve on a food
    /// card is not blocked while the SSE is still winding down.
    private func waitForReplyStop() async {
        guard let replyTask else { return }
        replyTask.cancel()
        await replyTask.value
        if self.replyTask == replyTask { self.replyTask = nil }
    }

    /// Drops fingerprints that include `approvalId`, so a failed send can go out once more.
    private func clearSentApproval(containing approvalId: String) {
        sentApprovals = Set(sentApprovals.filter { fingerprint in
            !fingerprint.split(separator: "|").map(String.init).contains(approvalId)
        })
    }

    /// Streams the server's answer to `turn` into the coach turn `id`, building its parts chunk
    /// by chunk. The coach turn takes the id the server gives it, which is the one it saves.
    private func stream(into id: String, turn: CoachMessage, history: [CoachMessage]) async {
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
            let request = await chatRequest(turn: turn, history: history, token: token)
            var assembler = CoachUIMessageAssembler(parts: messages.first { $0.id == id }?.parts ?? [])
            var answerId = id

            for try await chunk in client.reply(to: request, token: token) {
                try Task.checkCancellation()
                assembler.apply(chunk)
                guard let index = messages.firstIndex(where: { $0.id == answerId }) else { break }
                if let serverId = assembler.messageId, serverId != answerId {
                    messages[index] = messages[index].reidentified(as: serverId)
                    answerId = serverId
                }
                messages[index].parts = assembler.parts
                messages[index].text = assembler.text
            }

            // An answer that never arrived is not an answer; leaving the empty bubble would
            // read as the coach having nothing to say.
            if !CoachUIParts.hasContent(assembler.parts) {
                dropEmptyAnswer()
                failure = "Le coach n'a pas répondu. Réessaie."
                CoachReplyLiveActivityController.shared.markFailed()
            } else {
                CoachReplyLiveActivityController.shared.markReady(
                    preview: CoachReplyPreview.line(from: assembler.text)
                )
            }
            if CoachUIParts.appliedChanges(assembler.parts) > appliedBefore {
                onCalendarChanged?()
            }
        } catch is CancellationError {
            // Keep any words already shown; do not pull a fuller answer the athlete cancelled.
            dropEmptyAnswer()
            if userStoppedReply {
                failure = "Réponse arrêtée."
            }
            userStoppedReply = false
            CoachReplyLiveActivityController.shared.end()
        } catch let error as SharpitAPIError where error == .unauthorized {
            markContinuationFailed(id: id, message: "Session expirée. Reconnecte-toi.")
            dropEmptyAnswer()
            failure = "Session expirée. Reconnecte-toi."
            CoachReplyLiveActivityController.shared.markFailed()
        } catch let error as CoachChatError {
            let message = error.errorDescription ?? "La réponse n'a pas abouti. Réessaie."
            markContinuationFailed(id: id, message: message)
            dropEmptyAnswer()
            failure = error.errorDescription
            CoachReplyLiveActivityController.shared.markFailed()
        } catch {
            markContinuationFailed(id: id, message: "La réponse n'a pas abouti. Réessaie.")
            dropEmptyAnswer()
            failure = "La réponse n'a pas abouti. Réessaie."
            CoachReplyLiveActivityController.shared.markFailed()
        }
    }

    /// An approval left as `approval-responded` after a cut stream would stick on « Envoi… ».
    /// Mark it failed and clear its fingerprint so « Réessayer » can fire once.
    private func markContinuationFailed(id: String, message: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              let parts = messages[index].parts
        else { return }
        if let fingerprint = CoachUIParts.approvalFingerprint(parts) {
            sentApprovals.remove(fingerprint)
        }
        messages[index].parts = CoachUIParts.markingFailedApprovals(parts, message: message)
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
        CoachReplyLiveActivityController.shared.end()
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
            endAnchorRevision += 1
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

    /// A stored conversation sends only the turn: the server reads the thread and saves the
    /// answer. The first question creates the conversation before it is sent. Where nothing is
    /// kept (previews), or when the conversation cannot be created, the whole thread goes and
    /// the answer is still shown, only not saved.
    private func chatRequest(turn: CoachMessage, history: [CoachMessage], token: String) async -> CoachChatRequest {
        guard let conversations else { return .thread(history) }
        if let conversationId {
            return .stored(conversationId: conversationId, message: turn)
        }
        do {
            let created = try await SharpitRetry.run {
                try await conversations.create(messages: [turn], token: token)
            }
            conversationId = created
            return .stored(conversationId: created, message: turn)
        } catch {
            return .thread(history)
        }
    }

    private func dropEmptyAnswer() {
        if let last = messages.last, last.role == .assistant, !CoachUIParts.hasContent(last.parts ?? []),
           last.text.isEmpty {
            messages.removeLast()
        }
    }
}
