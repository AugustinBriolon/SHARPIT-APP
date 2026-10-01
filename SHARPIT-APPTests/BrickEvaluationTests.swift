import Foundation
import Testing
@testable import Sharpit

private actor EvaluationRecorder {
    var stored: V1BrickEvaluation?
    private(set) var saves: [V1BrickEvaluation] = []
    var failReads = false

    init(stored: V1BrickEvaluation? = nil) { self.stored = stored }

    func read() throws -> V1BrickEvaluation? {
        if failReads { throw SharpitAPIError.badRequest }
        return stored
    }

    func record(_ evaluation: V1BrickEvaluation) { saves.append(evaluation) }
    func setFailReads() { failReads = true }
}

private struct StubEvaluationClient: BrickEvaluationServing {
    let recorder: EvaluationRecorder

    func evaluation(brickGroupId: String, token: String) async throws -> V1BrickEvaluation? {
        try await recorder.read()
    }

    func save(_ evaluation: V1BrickEvaluation, token: String) async throws {
        await recorder.record(evaluation)
    }
}

@MainActor
private func makeStore(_ recorder: EvaluationRecorder) -> BrickEvaluationStore {
    BrickEvaluationStore(
        brickGroupId: "brick-1",
        client: StubEvaluationClient(recorder: recorder),
        tokenProvider: { "token" },
        saveDelay: .seconds(60)
    )
}

/// Taps collapse into one write that carries every answer, the stored ones included.
@MainActor
@Test func brickTapsCollapseIntoOneWriteKeepingStoredAnswers() async {
    let recorder = EvaluationRecorder(
        stored: V1BrickEvaluation(brickGroupId: "brick-1", rpe: nil, transitionRating: nil, feeling: nil, notes: "T2 lente")
    )
    let store = makeStore(recorder)
    await store.load()

    store.setRPE(6)
    store.setRPE(8)
    store.setTransitionRating(2)
    store.setFeeling(.bad)
    await store.flush()

    let saves = await recorder.saves
    #expect(saves == [
        V1BrickEvaluation(brickGroupId: "brick-1", rpe: 8, transitionRating: 2, feeling: "Mal", notes: "T2 lente"),
    ])
    #expect(store.status == .saved)
}

/// Before the stored evaluation is read, a tap must not send a blank form over it.
@MainActor
@Test func nothingIsSentBeforeTheStoredEvaluationIsRead() async {
    let recorder = EvaluationRecorder()
    let store = makeStore(recorder)

    store.setRPE(5)
    await store.flush()

    #expect(await recorder.saves.isEmpty)
}

/// A read that fails leaves the tile honest, and nothing is written.
@MainActor
@Test func aFailedReadMakesTheEvaluationUnavailable() async {
    let recorder = EvaluationRecorder()
    await recorder.setFailReads()
    let store = makeStore(recorder)

    await store.load()
    store.setRPE(5)
    await store.flush()

    #expect(store.phase == .unavailable("Évaluation indisponible pour l'instant."))
    #expect(await recorder.saves.isEmpty)
}

/// A feeling the web wrote in words this app does not map survives an effort change.
@MainActor
@Test func anUnmappedBrickFeelingIsSentBackUntouched() async {
    let recorder = EvaluationRecorder(
        stored: V1BrickEvaluation(brickGroupId: "brick-1", rpe: 4, transitionRating: nil, feeling: "Fluide", notes: nil)
    )
    let store = makeStore(recorder)
    await store.load()
    #expect(!store.isEmpty)

    store.setRPE(5)
    await store.flush()

    #expect(await recorder.saves.first?.feeling == "Fluide")
}

/// Blank notes clear the field rather than store whitespace.
@MainActor
@Test func blankNotesGoOutAsNull() async {
    let recorder = EvaluationRecorder()
    let store = makeStore(recorder)
    await store.load()
    #expect(store.isEmpty)

    store.setNotes("   ")
    await store.flush()

    #expect(await recorder.saves.first?.notes == nil)
}

/// The server replaces every field: a cleared answer must go out as null, not be left out.
@Test func theRequestBodyCarriesNullsForClearedAnswers() throws {
    let body = try BrickEvaluationClient.body(
        for: V1BrickEvaluation(brickGroupId: "brick-1", rpe: 7, transitionRating: nil, feeling: nil, notes: nil)
    )
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(json["brickGroupId"] as? String == "brick-1")
    #expect(json["rpe"] as? Int == 7)
    #expect(json["transitionRating"] is NSNull)
    #expect(json["feeling"] is NSNull)
    #expect(json["notes"] is NSNull)
}

@Test func transitionRatingsReadTheWebHints() {
    #expect(BrickTransitionRating.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
    #expect(BrickTransitionRating.smooth.hint == "Enchaînement naturel, aucune rupture.")
}
