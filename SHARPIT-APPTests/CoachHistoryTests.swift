import Foundation
import Testing
@testable import Sharpit

// MARK: - Stored messages

private func stored(_ json: String) -> JSONValue {
    do {
        return try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    } catch {
        fatalError("fixture is not JSON: \(error)")
    }
}

@Test func aStoredTurnIsReadFromItsTextParts() {
    let message = CoachMessage(stored: stored("""
    { "id": "m1", "role": "assistant", "parts": [
        { "type": "text", "text": "Première" },
        { "type": "tool-plan", "state": "output-available" },
        { "type": "text", "text": "Seconde" }
    ] }
    """))
    #expect(message?.role == .assistant)
    #expect(message?.text == "Première\n\nSeconde")
}

@Test func aTurnWithAnUnknownRoleIsLeftOut() {
    #expect(CoachMessage(stored: stored(#"{ "id": "m1", "role": "system", "parts": [] }"#)) == nil)
}

@Test func aStoredSubjectComesBackAsAChip() {
    let message = CoachMessage(stored: stored("""
    { "id": "m1", "role": "user", "parts": [{ "type": "text", "text": "Et ça ?" }],
      "metadata": { "discussKind": "planned-session", "sessionId": "s-1" } }
    """))
    #expect(message?.context?.target == .plannedSession(sessionId: "s-1"))
}

@Test func aSubjectTheAppCannotReachReadsAsAnOrdinaryTurn() {
    let message = CoachMessage(stored: stored("""
    { "id": "m1", "role": "user", "parts": [{ "type": "text", "text": "Et ça ?" }],
      "metadata": { "discussKind": "goal", "goalId": "g-1" } }
    """))
    #expect(message?.context == nil)
}

@Test(arguments: [
    (#"{ "discussKind": "planning", "horizonDays": 7 }"#, 7),
    (#"{ "discussKind": "planning", "horizonDays": "7" }"#, 7),
])
func aPlanningHorizonIsReadWhetherTheWebOrTheAppWroteIt(json: String, days: Int) {
    #expect(CoachDiscussContext(storedMetadata: stored(json))?.target == .planning(horizonDays: days))
}

@Test func savingSendsAStoredTurnBackAsItCame() throws {
    let toolPart = #"{ "type": "tool-plan", "state": "output-available" }"#
    let original = try #require(CoachMessage(stored: stored("""
    { "id": "m1", "role": "assistant", "parts": [
        { "type": "text", "text": "Voilà" }, \(toolPart)
    ] }
    """)))

    let body = try CoachConversationClient.body(for: [original])
    let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let parts = ((sent?["messages"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]]

    #expect(parts?.count == 2)
    #expect(parts?.last?["type"] as? String == "tool-plan")
}

@Test func savingSendsATurnWrittenHereAsTheChatRouteReadsIt() throws {
    let body = try CoachConversationClient.body(for: [CoachMessage(id: "m1", role: .user, text: "Bonjour")])
    let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let first = (sent?["messages"] as? [[String: Any]])?.first

    #expect(first?["id"] as? String == "m1")
    #expect(first?["role"] as? String == "user")
    #expect(((first?["parts"] as? [[String: Any]])?.first?["text"]) as? String == "Bonjour")
}

// MARK: - Store

private actor Saved {
    private(set) var created: [[CoachMessage]] = []
    private(set) var deleted: [String] = []

    func recordCreate(_ messages: [CoachMessage]) { created.append(messages) }
    func recordDelete(_ id: String) { deleted.append(id) }
}

/// Mutable so a cut stream can be followed by a fuller server thread in the same test.
private final class StubConversations: CoachConversationServing, @unchecked Sendable {
    var list: [CoachConversationSummary] = []
    var opened: CoachConversation?
    var failing = false
    /// Lets create succeed while the first GET after a cut stream still fails.
    var fetchFailuresRemaining = 0
    let saved: Saved
    private(set) var fetchCount = 0

    init(
        list: [CoachConversationSummary] = [],
        opened: CoachConversation? = nil,
        failing: Bool = false,
        fetchFailuresRemaining: Int = 0,
        saved: Saved = Saved()
    ) {
        self.list = list
        self.opened = opened
        self.failing = failing
        self.fetchFailuresRemaining = fetchFailuresRemaining
        self.saved = saved
    }

    func conversations(token: String) async throws -> [CoachConversationSummary] {
        if failing { throw SharpitAPIError.transport }
        return list
    }

    func conversation(id: String, token: String) async throws -> CoachConversation {
        fetchCount += 1
        if fetchFailuresRemaining > 0 {
            fetchFailuresRemaining -= 1
            throw SharpitAPIError.server
        }
        guard let opened, !failing else { throw SharpitAPIError.server }
        return opened
    }

    func create(messages: [CoachMessage], token: String) async throws -> String {
        if failing { throw SharpitAPIError.transport }
        await saved.recordCreate(messages)
        return "conversation-1"
    }

    func delete(id: String, token: String) async throws {
        if failing { throw SharpitAPIError.server }
        await saved.recordDelete(id)
    }
}

/// Answers « Oui » to every turn, and keeps what each turn sent.
private final class RecordingCoachClient: CoachChatServing, @unchecked Sendable {
    private(set) var requests: [CoachChatRequest] = []

    func reply(to request: CoachChatRequest, token: String) -> AsyncThrowingStream<JSONValue, Error> {
        requests.append(request)
        return StubCoachClient(deltas: ["Oui"]).reply(to: request, token: token)
    }

    /// The conversation id and the turn text of request `index`, when it went as a stored one.
    func stored(_ index: Int) -> (id: String, text: String)? {
        guard requests.indices.contains(index),
              case .stored(let id, let message) = requests[index] else { return nil }
        return (id, message.text)
    }
}

@MainActor
private func coachStore(
    opened: CoachConversation? = nil,
    failing: Bool = false,
    saved: Saved = Saved(),
    client: any CoachChatServing = RecordingCoachClient(),
    conversations: StubConversations? = nil,
    resyncDelay: Duration = .milliseconds(10)
) -> CoachStore {
    CoachStore(
        client: client,
        conversations: conversations ?? StubConversations(opened: opened, failing: failing, saved: saved),
        tokenProvider: { "token" },
        resyncDelay: resyncDelay
    )
}

/// Yields a partial answer, then cancels — the phone left mid-stream.
private struct CancellingCoachClient: CoachChatServing {
    func reply(to request: CoachChatRequest, token: String) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            StubCoachClient.textChunks(["Cou"]).forEach { continuation.yield($0) }
            continuation.finish(throwing: CancellationError())
        }
    }
}

/// Yields a first word, then hangs until the consumer cancels (composer stop).
private struct HangingCoachClient: CoachChatServing {
    func reply(to request: CoachChatRequest, token: String) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in StubCoachClient.textChunks(["Partiel"]) {
                    continuation.yield(chunk)
                }
                try? await Task.sleep(for: .seconds(30))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
private func ask(_ store: CoachStore, _ text: String = "Bonjour") async {
    store.draft = text
    await store.send()
}

@MainActor
@Test func theFirstQuestionCreatesTheConversationThenGoesAlone() async {
    let saved = Saved()
    let client = RecordingCoachClient()
    let store = coachStore(saved: saved, client: client)

    await ask(store)

    #expect(store.conversationId == "conversation-1")
    #expect(await saved.created.first?.map(\.role) == [.user])
    #expect(client.stored(0)?.id == "conversation-1")
    #expect(client.stored(0)?.text == "Bonjour")
}

@MainActor
@Test func laterQuestionsSendOnlyThemselves() async {
    let saved = Saved()
    let client = RecordingCoachClient()
    let store = coachStore(saved: saved, client: client)
    await ask(store, "Une")
    await ask(store, "Deux")

    #expect(await saved.created.count == 1)
    #expect(client.stored(1)?.id == "conversation-1")
    #expect(client.stored(1)?.text == "Deux")
}

@MainActor
@Test func aConversationThatCannotBeCreatedStillGetsAnAnswer() async {
    let client = RecordingCoachClient()
    let store = coachStore(failing: true, client: client)

    await ask(store)

    #expect(store.messages.map(\.role) == [.user, .assistant])
    #expect(store.failure == nil)
    #expect(store.conversationId == nil)
    #expect(client.requests.first == .thread([store.messages[0]]))
}

@MainActor
@Test func aNewConversationStartsEmptyAndIsCreatedAgain() async {
    let saved = Saved()
    let store = coachStore(saved: saved)
    await ask(store)

    store.startNewConversation()
    #expect(store.isEmpty)
    #expect(store.conversationId == nil)

    await ask(store, "Autre sujet")
    #expect(await saved.created.count == 2)
}

@MainActor
@Test func openingAConversationReplacesTheThreadAndContinuesIt() async {
    let saved = Saved()
    let past = CoachConversation(
        id: "past-1",
        messages: [CoachMessage(id: "a", role: .user, text: "Hier"), CoachMessage(id: "b", role: .assistant, text: "Oui")]
    )
    let client = RecordingCoachClient()
    let store = coachStore(opened: past, saved: saved, client: client)
    await ask(store, "Brouillon")

    let opened = await store.open(conversationId: "past-1")
    #expect(opened)
    #expect(store.messages.map(\.id) == ["a", "b"])
    #expect(store.conversationId == "past-1")
    #expect(store.endAnchorRevision == 1)

    await ask(store, "Suite")
    #expect(client.stored(1)?.id == "past-1")
    #expect(client.stored(1)?.text == "Suite")
}

@MainActor
@Test func stoppingAReplyCancelsTheStreamAndClearsIsReplying() async {
    let store = coachStore(client: HangingCoachClient())
    store.draft = "Stoppe-moi"
    let send = Task { await store.send() }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(store.isReplying)
    store.stopReply()
    await send.value
    #expect(!store.isReplying)
    #expect(store.messages.last?.role == .assistant)
    #expect(store.messages.last?.text.contains("Partiel") == true)
}

@MainActor
@Test func aCutStreamPullsTheSavedAnswerAndAnchorsTheEnd() async {
    let conversations = StubConversations(
        opened: CoachConversation(
            id: "conversation-1",
            messages: [
                CoachMessage(id: "q", role: .user, text: "Je doute"),
                CoachMessage(id: "a", role: .assistant, text: "Réponse complète du serveur."),
            ]
        )
    )
    let store = coachStore(client: CancellingCoachClient(), conversations: conversations)

    await ask(store, "Je doute")
    // Partial text stayed until the delayed pull; wait for it.
    try? await Task.sleep(for: .milliseconds(40))

    #expect(store.messages.last?.text == "Réponse complète du serveur.")
    #expect(store.endAnchorRevision >= 1)
    #expect(conversations.fetchCount >= 1)
    #expect(store.failure == nil)
}

@MainActor
@Test func resumeAfterInterruptionRetriesAFailedPull() async {
    let conversations = StubConversations(
        opened: CoachConversation(
            id: "conversation-1",
            messages: [
                CoachMessage(id: "q", role: .user, text: "Coupe"),
                CoachMessage(id: "a", role: .assistant, text: "Reprise."),
            ]
        ),
        fetchFailuresRemaining: 1
    )
    let store = coachStore(client: CancellingCoachClient(), conversations: conversations)

    await ask(store, "Coupe")
    try? await Task.sleep(for: .milliseconds(40))
    #expect(store.messages.last?.text == "Cou")

    await store.resumeAfterInterruption()

    #expect(store.messages.last?.text == "Reprise.")
}

@MainActor
@Test func aConversationThatCannotBeOpenedLeavesTheThreadAlone() async {
    let store = coachStore(opened: nil)
    await ask(store)

    let opened = await store.open(conversationId: "missing")

    #expect(!opened)
    #expect(store.messages.count == 2)
    #expect(store.failure == "Cette conversation n'a pas pu être ouverte.")
}

@MainActor
@Test func deletingTheOpenConversationClearsTheThread() async {
    let store = coachStore()
    await ask(store)

    store.forget(conversationId: "another")
    #expect(!store.isEmpty)

    store.forget(conversationId: "conversation-1")
    #expect(store.isEmpty)
    #expect(store.conversationId == nil)
}

// MARK: - History

private func summary(_ id: String) -> CoachConversationSummary {
    CoachConversationSummary(id: id, title: "Titre \(id)", updatedAt: Date(timeIntervalSince1970: 1_789_000_000))
}

@MainActor
private func history(
    list: [CoachConversationSummary],
    failing: Bool = false,
    saved: Saved = Saved(),
    onDeleted: @escaping (String) -> Void = { _ in }
) -> CoachHistoryStore {
    CoachHistoryStore(
        conversations: StubConversations(list: list, failing: failing, saved: saved),
        tokenProvider: { "token" },
        onDeleted: onDeleted
    )
}

@MainActor
@Test func historyListsTheConversations() async {
    let store = history(list: [summary("a"), summary("b")])
    await store.load()
    #expect(store.phase == .loaded([summary("a"), summary("b")]))
}

@MainActor
@Test func historyReportsWhenItCannotLoad() async {
    let store = history(list: [], failing: true)
    await store.load()
    #expect(store.phase == .failed("L'historique n'a pas pu être chargé."))
}

@MainActor
@Test func deletingRemovesTheRowAndTellsTheThread() async {
    let saved = Saved()
    var told: [String] = []
    let store = history(list: [summary("a"), summary("b")], saved: saved, onDeleted: { told.append($0) })
    await store.load()

    await store.delete(summary("a"))

    #expect(store.phase == .loaded([summary("b")]))
    #expect(await saved.deleted == ["a"])
    #expect(told == ["a"])
}

@MainActor
@Test func aRefusedDeletionBringsTheRowBack() async {
    // The list loads through a stub that works, then the delete goes through a failing one.
    let store = CoachHistoryStore(
        conversations: FailingDeletes(list: [summary("a")]),
        tokenProvider: { "token" },
        onDeleted: { _ in Issue.record("must not announce a deletion that failed") }
    )
    await store.load()

    await store.delete(summary("a"))

    #expect(store.phase == .loaded([summary("a")]))
    #expect(store.deletionFailure == "La conversation n'a pas pu être supprimée.")
}

private struct FailingDeletes: CoachConversationServing {
    let list: [CoachConversationSummary]

    func conversations(token: String) async throws -> [CoachConversationSummary] { list }
    func conversation(id: String, token: String) async throws -> CoachConversation { throw SharpitAPIError.server }
    func create(messages: [CoachMessage], token: String) async throws -> String { "x" }
    func delete(id: String, token: String) async throws { throw SharpitAPIError.server }
}

// MARK: - Wire

@Test func summariesDecodeTheServersTimestamps() throws {
    let json = """
    [{ "id": "c1", "title": "Ma semaine", "createdAt": "2026-09-19T08:00:00.000Z", "updatedAt": "2026-09-20T09:30:00.123Z" },
     { "id": "c2", "title": "Sans fraction", "createdAt": "2026-09-19T08:00:00Z", "updatedAt": "2026-09-20T09:30:00Z" }]
    """
    let list = try JSONDecoder().decode([CoachConversationSummary].self, from: Data(json.utf8))
    #expect(list.map(\.title) == ["Ma semaine", "Sans fraction"])
    #expect(list[0].updatedAt > list[1].updatedAt)
}

@Test func aStoredNutritionTurnKeepsItsDay() {
    let json = #"{ "discussKind": "nutrition", "trainingDayId": "2026-10-01" }"#
    #expect(CoachDiscussContext(storedMetadata: stored(json))?.target == .nutrition(trainingDayId: "2026-10-01"))
}
