import Testing
@testable import Sharpit

@MainActor
@Suite struct LaunchCurtainTests {
    @Test func staysUpUntilReady() {
        let curtain = LaunchCurtain()
        curtain.minimumElapsed()
        #expect(curtain.isUp)
        curtain.markReady()
        #expect(!curtain.isUp)
    }

    @Test func readyBeforeTheMinimumWaitsForIt() {
        let curtain = LaunchCurtain()
        curtain.markReady()
        #expect(curtain.isUp)
        curtain.minimumElapsed()
        #expect(!curtain.isUp)
    }

    @Test func timeoutLiftsWithoutReady() {
        let curtain = LaunchCurtain()
        curtain.timedOut()
        #expect(!curtain.isUp)
    }

    @Test func liftsOnceThroughTheAnimation() {
        var lifts = 0
        let curtain = LaunchCurtain { body in
            lifts += 1
            body()
        }
        curtain.markReady()
        curtain.minimumElapsed()
        curtain.timedOut()
        curtain.markReady()
        #expect(lifts == 1)
        #expect(!curtain.isUp)
    }

    @Test func runLiftsAtTheTimeoutWhenNothingIsReady() async {
        let curtain = LaunchCurtain()
        await curtain.run(minimum: .milliseconds(1), timeout: .milliseconds(5))
        #expect(!curtain.isUp)
    }

    @Test func runLiftsAfterTheMinimumWhenAlreadyReady() async {
        let curtain = LaunchCurtain()
        curtain.markReady()
        let run = Task { await curtain.run(minimum: .milliseconds(1), timeout: .seconds(60)) }
        // Lifted by the floor, long before the ceiling.
        for _ in 0..<200 where curtain.isUp { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(!curtain.isUp)
        run.cancel()
    }
}
