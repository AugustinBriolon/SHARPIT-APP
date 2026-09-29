import Foundation
import Testing
@testable import Sharpit

private actor Attempts {
    private(set) var count = 0
    private(set) var pauses: [Duration] = []

    func next() -> Int {
        count += 1
        return count
    }

    func paused(_ duration: Duration) { pauses.append(duration) }
}

@Test func aTransientFailureIsTriedAgainUntilItLands() async throws {
    let attempts = Attempts()

    let value = try await SharpitRetry.run(sleep: { await attempts.paused($0) }) {
        if await attempts.next() < 3 { throw SharpitAPIError.server }
        return "saved"
    }

    #expect(value == "saved")
    #expect(await attempts.count == 3)
    #expect(await attempts.pauses == [.seconds(1), .seconds(2)])
}

@Test func aWriteThatKeepsFailingGivesUpAfterFourTries() async {
    let attempts = Attempts()

    await #expect(throws: SharpitAPIError.transport) {
        try await SharpitRetry.run(sleep: { await attempts.paused($0) }) {
            _ = await attempts.next()
            throw SharpitAPIError.transport
        }
    }

    #expect(await attempts.count == SharpitRetry.attempts)
    #expect(await attempts.pauses == [.seconds(1), .seconds(2), .seconds(4)])
}

/// Sending a refused request again gets the same answer: it is said at once.
@Test func aRefusalIsNotTriedAgain() async {
    let attempts = Attempts()

    await #expect(throws: SharpitAPIError.badRequest) {
        try await SharpitRetry.run(sleep: { await attempts.paused($0) }) {
            _ = await attempts.next()
            throw SharpitAPIError.badRequest
        }
    }

    #expect(await attempts.count == 1)
}

@Test func onlyTheNetworkAndTheServerFailingAreTransient() {
    #expect(SharpitRetry.isTransient(SharpitAPIError.transport))
    #expect(SharpitRetry.isTransient(SharpitAPIError.server))
    #expect(SharpitRetry.isTransient(SharpitAPIError.rateLimited))
    #expect(SharpitRetry.isTransient(URLError(.timedOut)))
    #expect(!SharpitRetry.isTransient(SharpitAPIError.unauthorized))
    #expect(!SharpitRetry.isTransient(SharpitAPIError.badRequest))
    #expect(!SharpitRetry.isTransient(SharpitAPIError.message("Objectif invalide")))
}
