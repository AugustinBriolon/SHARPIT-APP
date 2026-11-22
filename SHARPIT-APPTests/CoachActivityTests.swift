import Testing
@testable import Sharpit

/// What the thread says the coach is doing, read from the turn's parts as the route streams them.

private func parts(_ chunks: [String]) -> [JSONValue] {
    var assembler = CoachUIMessageAssembler()
    chunks.forEach { assembler.apply(chunk($0)) }
    return assembler.parts
}

@Test func beforeTheServerAnswersTheCoachReadsTheAthletesData() {
    #expect(CoachActivity.current(parts: []) == .gathering)
}

@Test func aStepOpenedWithoutWordsIsTheModelThinking() {
    #expect(CoachActivity.current(parts: parts([#"{"type":"start-step"}"#])) == .thinking)
}

@Test func aToolBeingCalledIsNamed() {
    let turn = parts([
        #"{"type":"start-step"}"#,
        #"{"type":"tool-input-available","toolCallId":"a","toolName":"listPlannedSessions","input":{}}"#,
    ])
    #expect(CoachActivity.current(parts: turn) == .tool("tool-listPlannedSessions"))
    #expect(CoachActivity.tool("tool-listPlannedSessions").label == "Lecture de ton plan")
}

@Test func onceAToolAnsweredTheCoachAnalysesUntilItWrites() {
    let read = [
        #"{"type":"start-step"}"#,
        #"{"type":"tool-input-available","toolCallId":"a","toolName":"listPlannedSessions","input":{}}"#,
        #"{"type":"tool-output-available","toolCallId":"a","output":{"ok":true}}"#,
    ]
    #expect(CoachActivity.current(parts: parts(read)) == .analysing)
    #expect(CoachActivity.current(parts: parts(read + [#"{"type":"finish-step"}"#, #"{"type":"start-step"}"#])) == .analysing)
}

@Test func wordsArrivingSayNothingMore() {
    let turn = parts([
        #"{"type":"start-step"}"#,
        #"{"type":"text-start","id":"t"}"#,
        #"{"type":"text-delta","id":"t","delta":"Ta nuit"}"#,
    ])
    #expect(CoachActivity.current(parts: turn) == nil)
}

@Test func aTextPartOpenedWithoutAWordIsStillTheWait() {
    let turn = parts([#"{"type":"start-step"}"#, #"{"type":"text-start","id":"t"}"#])
    #expect(CoachActivity.current(parts: turn) == .thinking)
}

@Test func aProposalWaitingForAnAnswerSaysNothing() {
    let turn = parts([
        #"{"type":"start-step"}"#,
        #"{"type":"tool-input-available","toolCallId":"a","toolName":"createPlannedSession","input":{}}"#,
        #"{"type":"tool-approval-request","toolCallId":"a","approvalId":"ap"}"#,
    ])
    #expect(CoachActivity.current(parts: turn) == nil)
}

@Test func anApprovedChangeIsBeingApplied() {
    let turn = CoachUIParts.responding(
        parts([
            #"{"type":"start-step"}"#,
            #"{"type":"tool-input-available","toolCallId":"a","toolName":"createPlannedSession","input":{}}"#,
            #"{"type":"tool-approval-request","toolCallId":"a","approvalId":"ap"}"#,
        ]),
        approvalId: "ap",
        approved: true
    )
    #expect(CoachActivity.current(parts: turn) == .applying)
}

@Test func followUpSuggestionsAreNotAnnounced() {
    let turn = parts([
        #"{"type":"start-step"}"#,
        #"{"type":"tool-input-available","toolCallId":"a","toolName":"suggestFollowUps","input":{"suggestions":["Et demain ?"]}}"#,
    ])
    #expect(CoachActivity.current(parts: turn) == nil)
}

@Test func aToolTheAppDoesNotKnowStillReadsAsData() {
    #expect(CoachActivity.tool("tool-somethingNew").label == "Lecture de tes données")
}
