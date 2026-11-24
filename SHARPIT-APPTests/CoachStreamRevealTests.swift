import Testing
@testable import Sharpit

@Test func aLineIsHiddenUntilTheStreamReachesItThenFadesInWhole() {
    let edge = SharpitFadeFrontRenderer.edge
    // The front is still on the line before: nothing of this one shows.
    #expect(SharpitFadeFrontRenderer.opacity(front: 40, lineStart: 40) == 0)
    #expect(SharpitFadeFrontRenderer.opacity(front: 30, lineStart: 40) == 0)
    // A few glyphs in, the whole line is on its way; past the edge it is simply there.
    #expect(SharpitFadeFrontRenderer.opacity(front: 40 + edge / 2, lineStart: 40) == 0.5)
    #expect(SharpitFadeFrontRenderer.opacity(front: 40 + edge, lineStart: 40) == 1)
    #expect(SharpitFadeFrontRenderer.opacity(front: 400, lineStart: 40) == 1)
}

@Test func anEmptyThreadOffersThreeStartingPointsAndThePlusKeepsThemAll() {
    #expect(CoachQuickAction.suggested == [.adjustWeek, .adjustSession, .tiredOrHurt])
    #expect(CoachQuickAction.allCases.count == 5)
}
