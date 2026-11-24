import Foundation
import Testing
@testable import Sharpit

@Test func thePaywallListsEverythingProAddsOnce() {
    let perks = ProPerkLine.all
    // The ten perks the server lists (`pro-perks.ts`), each under its id.
    #expect(perks.map(\.id) == [
        "coach", "adaptive-plan", "weekly-review", "session-analysis", "journal-coach-read",
        "nutrition-reading", "biological-age", "watch-push", "extra-widgets", "support",
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

@Test func theListRisesAtItsSpeedWhenThePaywallOpens() {
    // Eased in from rest, then steady: past the ramp it has lost half the ramp's travel.
    let ramp = ConveyorLoop.resumeRamp
    #expect(ConveyorLoop.offset(from: 100, elapsed: 0, fling: 0, delay: 0) == 100)
    #expect(abs(ConveyorLoop.offset(from: 100, elapsed: ramp + 2, fling: 0, delay: 0) - (100 + ConveyorLoop.speed * (2 + ramp / 2))) < 0.001)
}

@Test func aTouchHoldsTheListThenTheRiseEasesBackIn() {
    let delay = ConveyorLoop.resumeDelay
    // Released without a flick: nothing moves until the wait is over.
    #expect(ConveyorLoop.offset(from: 100, elapsed: delay - 0.1, fling: 0, delay: delay) == 100)
    // Then the speed grows without a step: each tenth of a second covers more than the last.
    let steps = (0...6).map { ConveyorLoop.rise(after: Double($0) * 0.1) }
    let gains = zip(steps.dropFirst(), steps).map { $0 - $1 }
    #expect(gains == gains.sorted())
    #expect(gains[0] < ConveyorLoop.speed * 0.1 * 0.05)
    // And it meets the steady rise with no jump at the end of the ramp.
    let ramp = ConveyorLoop.resumeRamp
    #expect(abs(ConveyorLoop.rise(after: ramp + 0.001) - ConveyorLoop.rise(after: ramp - 0.001)) < ConveyorLoop.speed * 0.003)
}

@Test func aFlickDiesDownBeforeTheListSetsOffAgain() {
    let delay = ConveyorLoop.resumeDelay
    // A flick adds its travel, bounded, and has died down by the time the rise comes back.
    let thrown = ConveyorLoop.offset(from: 100, elapsed: delay, fling: 800, delay: delay)
    #expect(abs(thrown - (100 + 800 * ConveyorLoop.flingDecay)) < 2)
    // A flick the other way takes the list back.
    #expect(ConveyorLoop.offset(from: 100, elapsed: 0.2, fling: -800, delay: delay) < 100)
    #expect(ConveyorLoop.offset(from: 0, elapsed: 1, fling: 99_999, delay: delay) == ConveyorLoop.offset(from: 0, elapsed: 1, fling: ConveyorLoop.maxFling, delay: delay))
}
