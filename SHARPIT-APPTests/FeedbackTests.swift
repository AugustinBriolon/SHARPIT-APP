import Foundation
import Testing
@testable import Sharpit

/// Keeps what it was sent, or refuses as told.
private actor FeedbackInbox: FeedbackServing {
    private(set) var notes: [V1FeedbackNote] = []
    let refusal: SharpitAPIError?

    init(refusal: SharpitAPIError? = nil) { self.refusal = refusal }

    func sendFeedback(_ note: V1FeedbackNote, token _: String) async throws {
        if let refusal { throw refusal }
        notes.append(note)
    }
}

@MainActor
@Test func aNoteGoesOutTrimmedWithWhereItWasWrittenAndTheVersion() async {
    let inbox = FeedbackInbox()
    let store = FeedbackStore(client: inbox, tokenProvider: { "t" })
    store.message = "  Le plan est top  \n"

    await store.send()

    let notes = await inbox.notes
    #expect(notes == [V1FeedbackNote(message: "Le plan est top", context: "settings", appVersion: AppVersion.display)])
    #expect(store.isSent)
    #expect(store.message.isEmpty)
}

@MainActor
@Test func anEmptyNoteIsNotSent() async {
    let inbox = FeedbackInbox()
    let store = FeedbackStore(client: inbox, tokenProvider: { "t" })
    store.message = "   "

    #expect(!store.canSend)
    await store.send()

    #expect(await inbox.notes.isEmpty)
    #expect(!store.isSent)
}

@MainActor
@Test func aRefusedNoteComesBackAndSaysWhy() async {
    let store = FeedbackStore(client: FeedbackInbox(refusal: .message("Écris quelques mots avant d’envoyer.")), tokenProvider: { "t" })
    store.message = "Bug"

    await store.send()

    #expect(!store.isSent)
    #expect(store.message == "Bug")
    #expect(SharpitWriteFailures.shared.latest?.message == "Écris quelques mots avant d’envoyer.")
}

@Test func theServersAnswersMapToWhatTheAppSays() throws {
    try FeedbackClient.check(status: 201, body: Data())
    #expect(throws: SharpitAPIError.unauthorized) { try FeedbackClient.check(status: 401, body: Data()) }
    #expect(throws: SharpitAPIError.rateLimited) { try FeedbackClient.check(status: 429, body: Data()) }
    #expect(throws: SharpitAPIError.message("Trop court")) {
        try FeedbackClient.check(status: 400, body: Data(#"{"error":"Trop court"}"#.utf8))
    }
    #expect(throws: SharpitAPIError.server) { try FeedbackClient.check(status: 500, body: Data()) }
}
