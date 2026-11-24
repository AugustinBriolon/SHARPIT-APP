import Foundation
import Testing
@testable import Sharpit

@Test func thePaywallListsEverythingProAddsOnce() {
    let perks = ProPerkLine.all
    // The eleven perks the server lists (`pro-perks.ts`), each under its id.
    #expect(perks.map(\.id) == [
        "coach", "adaptive-plan", "weekly-review", "session-analysis", "journal-coach-read",
        "nutrition-reading", "biological-age", "watch-push", "extra-widgets", "early-access", "support",
    ])
    #expect(Set(perks.map(\.symbol)).count == perks.count)
    #expect(perks.allSatisfy { !$0.sentence.isEmpty })
}

@Test func theListComesBackToItsStartWhicheverWayItIsDragged() {
    #expect(ConveyorLoop.wrapped(0, length: 600) == 0)
    #expect(ConveyorLoop.wrapped(610, length: 600) == 10)
    #expect(ConveyorLoop.wrapped(1_810, length: 600) == 10)
    // Dragged down past the first line, the last one follows it.
    #expect(ConveyorLoop.wrapped(-10, length: 600) == 590)
    #expect(ConveyorLoop.wrapped(-1_210, length: 600) == 590)
    #expect(ConveyorLoop.wrapped(50, length: 0) == 0)
}

@Test func aFlickDiesDownIntoTheSteadyRise() {
    let rest = ConveyorLoop.offset(from: 100, elapsed: 2, fling: 0)
    #expect(rest == 100 + ConveyorLoop.speed * 2)
    // A flick adds its travel, bounded, and nothing more once it has died down.
    let thrown = ConveyorLoop.offset(from: 100, elapsed: 10, fling: 800)
    #expect(abs(thrown - (100 + ConveyorLoop.speed * 10 + 800 * ConveyorLoop.flingDecay)) < 0.01)
    // A flick the other way takes the list back before it rises again.
    #expect(ConveyorLoop.offset(from: 100, elapsed: 0.2, fling: -800) < 100)
    #expect(ConveyorLoop.offset(from: 0, elapsed: 1, fling: 99_999) == ConveyorLoop.offset(from: 0, elapsed: 1, fling: ConveyorLoop.maxFling))
}
