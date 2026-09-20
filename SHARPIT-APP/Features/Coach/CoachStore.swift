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

    /// What the next message will carry. Set when the athlete arrives from another screen,
    /// and droppable before sending.
    var pendingContext: CoachDiscussContext?

    var draft = ""

    private let client: any CoachChatServing
    private let tokenProvider: (() async throws -> String)?

    init(client: any CoachChatServing, tokenProvider: (() async throws -> String)?) {
        self.client = client
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
            }
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .unauthorized {
            dropEmptyAnswer()
            failure = "Session expirée. Reconnecte-toi."
        } catch {
            dropEmptyAnswer()
            failure = "La réponse n'a pas abouti. Réessaie."
        }
    }

    private func dropEmptyAnswer() {
        if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
            messages.removeLast()
        }
    }
}
