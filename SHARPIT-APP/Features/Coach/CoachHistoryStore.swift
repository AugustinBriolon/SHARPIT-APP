import Foundation
import Observation

/// The list of past conversations, and removing from it.
@MainActor
@Observable
final class CoachHistoryStore {
    enum Phase: Equatable {
        case loading
        case loaded([CoachConversationSummary])
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    /// Shown above the list when a deletion did not go through; the list is restored.
    private(set) var deletionFailure: String?

    private let conversations: any CoachConversationServing
    private let tokenProvider: () async throws -> String
    private let onDeleted: (String) -> Void

    init(
        conversations: any CoachConversationServing,
        tokenProvider: @escaping () async throws -> String,
        onDeleted: @escaping (String) -> Void
    ) {
        self.conversations = conversations
        self.tokenProvider = tokenProvider
        self.onDeleted = onDeleted
    }

    func load() async {
        phase = .loading
        do {
            phase = .loaded(try await conversations.conversations(token: try await tokenProvider()))
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .unauthorized {
            phase = .failed("Session expirée. Reconnecte-toi.")
        } catch {
            phase = .failed("L'historique n'a pas pu être chargé.")
        }
    }

    /// The row leaves at once and comes back if the server refuses, so a swipe feels done.
    func delete(_ summary: CoachConversationSummary) async {
        guard case .loaded(let list) = phase else { return }
        deletionFailure = nil
        phase = .loaded(list.filter { $0.id != summary.id })
        do {
            try await conversations.delete(id: summary.id, token: try await tokenProvider())
            onDeleted(summary.id)
        } catch {
            phase = .loaded(list)
            deletionFailure = "La conversation n'a pas pu être supprimée."
        }
    }
}
