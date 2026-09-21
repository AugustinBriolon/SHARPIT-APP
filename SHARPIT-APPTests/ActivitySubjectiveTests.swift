import Foundation
import Testing
@testable import Sharpit

// MARK: - Vocabulary

/// The web stores the word, not the step. Writing any other word hides the answer there.
@Test func feelingWritesTheWebsWords() {
    #expect(SessionFeeling.allCases.map(\.storedValue) == ["Très mal", "Mal", "Correct", "Bien", "Très bien"])
}

/// Earlier builds of the app wrote their own words; those sessions keep their value.
@Test func feelingReadsTheWebAndTheOldAppWords() {
    #expect(SessionFeeling(stored: "Très mal") == .veryBad)
    #expect(SessionFeeling(stored: "tres mauvais") == .veryBad)
    #expect(SessionFeeling(stored: "Mauvais") == .bad)
    #expect(SessionFeeling(stored: "Moyen") == .okay)
    #expect(SessionFeeling(stored: "Correct") == .okay)
    #expect(SessionFeeling(stored: "Très bien") == .veryGood)
    #expect(SessionFeeling(stored: "Fluide") == nil)
    #expect(SessionFeeling(stored: nil) == nil)
}

@Test func verdictsReadInFrenchNotAsEnums() {
    #expect(SessionVerdict(rawValue: "AS_PLANNED")?.label == "Conforme")
    #expect(SessionVerdict(rawValue: "HARDER")?.label == "Plus dur que prévu")
    #expect(SessionVerdict(rawValue: "UNKNOWN") == nil)
}

@Test func complianceTonesFollowTheScoreBands() {
    #expect(SessionFeedbackTone.compliance(95) == SharpitColor.signalRecovery)
    #expect(SessionFeedbackTone.compliance(70) == SharpitColor.signalCaution)
    #expect(SessionFeedbackTone.compliance(40) == SharpitColor.signalRisk)
}

@Test func effortClimbsTheIntensityRamp() {
    #expect(SessionFeedbackTone.effort(1) == SharpitColor.signalRecovery)
    #expect(SessionFeedbackTone.effort(6) == SharpitColor.signalTempo)
    #expect(SessionFeedbackTone.effort(10) == SharpitColor.signalVo2)
}

// MARK: - Store

private actor SubjectiveRecorder {
    private(set) var writes: [(rpe: Double?, feeling: String?)] = []
    var failNext = false

    func record(_ rpe: Double?, _ feeling: String?) throws {
        if failNext {
            failNext = false
            throw SharpitAPIError.server
        }
        writes.append((rpe, feeling))
    }

    func setFailNext() { failNext = true }
}

private struct StubSubjectiveClient: ActivityServing {
    let recorder: SubjectiveRecorder

    func activities(token: String) async throws -> [V1ActivityListItem] { [] }
    func activity(id: String, token: String) async throws -> V1ActivityDetail { throw SharpitAPIError.server }
    func activityStream(id: String, token: String) async throws -> V1ActivityStreamPayload { throw SharpitAPIError.server }
    func generateNarrative(id: String, token: String) async throws -> V1ActivityDetail { throw SharpitAPIError.server }
    func updateSubjective(id: String, rpe: Double?, feeling: String?, token: String) async throws {
        try await recorder.record(rpe, feeling)
    }
}

@MainActor
private func makeStore(
    recorder: SubjectiveRecorder,
    rpe: Double? = nil,
    feeling: String? = nil,
    onSaved: @escaping (Double?, String?) -> Void = { _, _ in }
) -> ActivitySubjectiveStore {
    ActivitySubjectiveStore(
        activityId: "run-1",
        rpe: rpe,
        feeling: feeling,
        client: StubSubjectiveClient(recorder: recorder),
        tokenProvider: { "token" },
        saveDelay: .seconds(60),
        onSaved: onSaved
    )
}

/// Moving along the scale costs one write, carrying both answers.
@MainActor
@Test func tapsCollapseIntoOneWriteWithBothAnswers() async {
    let recorder = SubjectiveRecorder()
    var saved: (Double?, String?)?
    let store = makeStore(recorder: recorder) { saved = ($0, $1) }

    store.setRPE(6)
    store.setRPE(7)
    store.setFeeling(.good)
    await store.flush()

    let writes = await recorder.writes
    #expect(writes.count == 1)
    #expect(writes.first?.rpe == 7)
    #expect(writes.first?.feeling == "Bien")
    #expect(saved?.0 == 7)
    #expect(store.status == .saved)
}

/// Closing the drawer after the write already went out must not send it again.
@MainActor
@Test func closingAfterASaveSendsNothingMore() async {
    let recorder = SubjectiveRecorder()
    let store = makeStore(recorder: recorder)

    store.setRPE(5)
    await store.flush()
    await store.flush()

    #expect(await recorder.writes.count == 1)
}

/// A word the app cannot map survives a change of effort alone.
@MainActor
@Test func anUnmappedFeelingIsSentBackUntouched() async {
    let recorder = SubjectiveRecorder()
    let store = makeStore(recorder: recorder, rpe: 4, feeling: "Fluide")

    store.setRPE(5)
    await store.flush()

    #expect(await recorder.writes.first?.feeling == "Fluide")
}

/// A failed write keeps the answer on screen, and tapping the same value retries it.
@MainActor
@Test func aFailedWriteCanBeRetriedWithTheSameValue() async {
    let recorder = SubjectiveRecorder()
    await recorder.setFailNext()
    let store = makeStore(recorder: recorder)

    store.setRPE(8)
    await store.flush()
    #expect(store.rpe == 8)
    if case .failed = store.status {} else { Issue.record("expected a failure") }

    store.setRPE(8)
    await store.flush()
    #expect(await recorder.writes.map(\.rpe) == [8])
    #expect(store.status == .saved)
}
