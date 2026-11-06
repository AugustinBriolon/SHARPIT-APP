import Foundation
import Testing
@testable import Sharpit

private func prescription(_ sets: [JSONValue]) -> JSONValue {
    .object(["version": .number(1), "sets": .array(sets)])
}

private let hipStretch: JSONValue = .object([
    "exercise": .string("Étirement des fléchisseurs de la hanche"),
    "sets": .number(3),
    "reps": .number(0),
    "durationSec": .number(30),
    "perSide": .bool(true),
    "order": .number(0),
])

@Test func aOneSidedHoldReadsAsSecondsPerSide() throws {
    let session = try #require(GuidedStrengthSession.make(title: "Mobilité", plannedSessionId: nil, prescription: prescription([hipStretch])))
    #expect(session.targets.count == 3)
    #expect(session.targets[0].perSide)
    #expect(session.targets[0].isHold)
    #expect(session.targets[0].targetLine == "30 s par côté")
    #expect(session.targets[0].readoutLine == "30 s par côté")
}

@Test func noLoadIsNeverReadAsZeroKilos() throws {
    let pushUp: JSONValue = .object([
        "exercise": .string("Pompe"), "sets": .number(1), "reps": .number(1), "weightKg": .number(0), "order": .number(0),
    ])
    let session = try #require(GuidedStrengthSession.make(title: "Renfo", plannedSessionId: nil, prescription: prescription([pushUp])))
    #expect(session.targets[0].readoutLine == "1 rep")
    #expect(session.targets[0].targetLine == "1 rep")
}

@Test func anAddedSetKeepsItsSides() throws {
    var session = try #require(GuidedStrengthSession.make(title: "Mobilité", plannedSessionId: nil, prescription: prescription([hipStretch])))
    session.addSet(toExercise: "Étirement des fléchisseurs de la hanche")
    #expect(session.targets.count == 4)
    let allSided = session.targets.allSatisfy(\.perSide)
    #expect(allSided)
}

@Test func aOneSidedHoldCountsInThenChainsBothSidesWithASwitch() {
    let clock = GuidedHoldClock(durationSec: 30, perSide: true)
    #expect(clock.totalSec == 5 + 30 + 5 + 30)
    #expect(clock.phase(elapsed: 0) == .running(.prepare, remaining: 5))
    #expect(clock.phase(elapsed: 5) == .running(.hold(side: 0), remaining: 30))
    #expect(clock.phase(elapsed: 34.9) == .running(.hold(side: 0), remaining: 1))
    #expect(clock.phase(elapsed: 35) == .running(.switchSides, remaining: 5))
    #expect(clock.phase(elapsed: 40) == .running(.hold(side: 1), remaining: 30))
    #expect(clock.phase(elapsed: 69) == .running(.hold(side: 1), remaining: 1))
    #expect(clock.phase(elapsed: 70) == .finished)
    #expect(clock.holds.map(\.seconds) == [30, 30])
}

@Test func theSecondSideIsAnnouncedBeforeItComes() {
    let clock = GuidedHoldClock(durationSec: 30, perSide: true)
    #expect(GuidedHoldPage.title(clock.phase(elapsed: 0)) == "Mets-toi en place")
    #expect(GuidedHoldPage.next(clock.phase(elapsed: 0), clock: clock) == "Ensuite : côté gauche, 30 s")
    #expect(GuidedHoldPage.next(clock.phase(elapsed: 10), clock: clock) == "Ensuite : côté droit, 30 s")
    #expect(GuidedHoldPage.title(clock.phase(elapsed: 36)) == "Change de côté")
    #expect(GuidedHoldPage.next(clock.phase(elapsed: 36), clock: clock) == "Ensuite : côté droit, 30 s")
    #expect(GuidedHoldPage.title(clock.phase(elapsed: 41)) == "Côté droit")
    #expect(GuidedHoldPage.next(clock.phase(elapsed: 41), clock: clock) == nil)
}

@Test func theButtonGoesToTheOtherSideBeforeEndingTheSet() {
    let clock = GuidedHoldClock(durationSec: 30, perSide: true)
    // Count-in → first side; first side or switch → second side; second side → done.
    #expect(clock.skipTarget(from: clock.phase(elapsed: 2)) == 5)
    #expect(GuidedHoldPage.actionTitle(clock.phase(elapsed: 2), clock: clock) == "Commencer")
    #expect(clock.skipTarget(from: clock.phase(elapsed: 12)) == 40)
    #expect(GuidedHoldPage.actionTitle(clock.phase(elapsed: 12), clock: clock) == "Passer au côté droit")
    #expect(clock.skipTarget(from: clock.phase(elapsed: 37)) == 40)
    #expect(GuidedHoldPage.actionTitle(clock.phase(elapsed: 37), clock: clock) == "Commencer le côté droit")
    #expect(clock.phase(elapsed: 40) == .running(.hold(side: 1), remaining: 30))
    #expect(clock.skipTarget(from: clock.phase(elapsed: 45)) == nil)
    #expect(GuidedHoldPage.actionTitle(clock.phase(elapsed: 45), clock: clock) == "Terminer la série")
}

@Test func aHoldWithoutSidesEndsTheSetFromItsHold() {
    let clock = GuidedHoldClock(durationSec: 45, perSide: false)
    #expect(clock.skipTarget(from: clock.phase(elapsed: 1)) == 5)
    #expect(clock.skipTarget(from: clock.phase(elapsed: 20)) == nil)
}

@Test func aHoldWithoutSidesIsCountedInThenOneCountdown() {
    let clock = GuidedHoldClock(durationSec: 45, perSide: false)
    #expect(clock.phase(elapsed: 2) == .running(.prepare, remaining: 3))
    #expect(clock.phase(elapsed: 15) == .running(.hold(side: nil), remaining: 35))
    #expect(clock.phase(elapsed: 50) == .finished)
    #expect(GuidedHoldPage.title(clock.phase(elapsed: 15)) == "Maintien")
}

@MainActor
@Test func theDockRunsOneSessionAndBringsItBack() throws {
    let dock = GuidedWorkoutDock()
    let first = try #require(GuidedStrengthSession.make(title: "A", plannedSessionId: nil, prescription: prescription([hipStretch])))
    let second = try #require(GuidedStrengthSession.make(title: "B", plannedSessionId: nil, prescription: prescription([hipStretch])))
    let finish = GuidedStrengthFinishContext(client: ActivityClient(), linker: PlannedSessionClient(), tokenProvider: { "t" })

    dock.start(first, finish: finish)
    dock.minimize()
    #expect(dock.isMinimized)

    // A second « Lancer la séance » brings back the one running rather than replacing it.
    dock.start(second, finish: finish)
    #expect(dock.active?.session.title == "A")
    #expect(!dock.isMinimized)

    dock.end()
    #expect(dock.active == nil)
    dock.minimize()
    #expect(!dock.isMinimized)
}
