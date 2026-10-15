import Foundation
import Testing
@testable import Sharpit

@MainActor
private final class RunCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}

@Test @MainActor func aFreshSuccessIsNotRunAgain() async {
    let gate = LoadGate(now: { Date(timeIntervalSince1970: 1_000) })
    let runs = RunCounter()

    #expect(await gate.run { runs.bump(); return true })
    #expect(await gate.run { runs.bump(); return true } == false)
    #expect(runs.count == 1)
}

@Test @MainActor func aForcedRunIgnoresFreshness() async {
    var clock = Date(timeIntervalSince1970: 1_000)
    let gate = LoadGate(now: { clock })
    let runs = RunCounter()

    #expect(await gate.run { runs.bump(); return true })
    #expect(await gate.run(force: true) { runs.bump(); return true })
    #expect(runs.count == 2)

    clock = clock.addingTimeInterval(LoadGate.tabStaleAfter + 1)
    #expect(await gate.run { runs.bump(); return true })
    #expect(runs.count == 3)
}

@Test @MainActor func concurrentCallersShareOneRun() async {
    let gate = LoadGate()
    let runs = RunCounter()

    async let a: Bool = gate.run {
        try? await Task.sleep(for: .milliseconds(30))
        runs.bump()
        return true
    }
    async let b: Bool = gate.run {
        runs.bump()
        return true
    }
    _ = await (a, b)
    #expect(runs.count == 1)
}

@Test @MainActor func aFailedRunDoesNotArmFreshness() async {
    let gate = LoadGate(now: { Date(timeIntervalSince1970: 1_000) })
    let runs = RunCounter()

    #expect(await gate.run { runs.bump(); return false } == false)
    #expect(await gate.run { runs.bump(); return true })
    #expect(runs.count == 2)
}
