import Foundation
import Observation

/// How a write reaches the server whatever happens: the screen has already shown the change,
/// so a dropped connection, a timeout or a 5xx is tried again in the background, and only a
/// write that keeps failing — or that the server refuses outright — comes back as an error.
///
/// A refusal (4xx, a session gone, a payload the server rejects) is not retried: sending the
/// same request again would get the same answer.
nonisolated enum SharpitRetry {
    /// The first try plus three more.
    static let attempts = 4

    /// 1 s, 2 s, 4 s between tries: about seven seconds before a failure is said.
    static func pause(beforeRetry retry: Int) -> Duration {
        .seconds(1 << (retry - 1))
    }

    /// No pause under the test host: a stub failing on purpose would hold every such test
    /// for seven seconds. `SharpitRetryTests` passes its own sleep to check the pauses.
    private static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static func defaultSleep(_ duration: Duration) async throws {
        guard !isTestHost else { return }
        try await Task.sleep(for: duration)
    }

    static func isTransient(_ error: any Error) -> Bool {
        switch error {
        case let error as SharpitAPIError:
            error == .transport || error == .server || error == .rateLimited
        case is URLError:
            true
        default:
            false
        }
    }

    /// Runs `operation`, trying a transient failure again up to `attempts` times. The token is
    /// asked inside the operation, so each try carries a fresh one.
    static func run<T>(
        attempts: Int = attempts,
        sleep: (Duration) async throws -> Void = defaultSleep,
        _ operation: () async throws -> T
    ) async throws -> T {
        var retry = 0
        while true {
            do {
                return try await operation()
            } catch {
                retry += 1
                guard retry < attempts, isTransient(error), !Task.isCancelled else { throw error }
                try await sleep(pause(beforeRetry: retry))
            }
        }
    }
}

/// Where a background write that failed for good is said. Stores cannot read the environment,
/// and a form may be closed by the time its write gives up, so the failure goes to this one
/// place and `RootView` shows it in the app's toast slot.
@MainActor
@Observable
final class SharpitWriteFailures {
    static let shared = SharpitWriteFailures()

    struct Failure: Equatable {
        let id = UUID()
        let message: String
    }

    private(set) var latest: Failure?

    func report(_ message: String) {
        latest = Failure(message: message)
    }
}
