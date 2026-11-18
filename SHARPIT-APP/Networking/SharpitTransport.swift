import Foundation

/// How a request leaves the app, for every client.
///
/// Two things used to read as « Pas de connexion » with the network up. A request cancelled with
/// the screen that asked for it (a tab left, a day turned, a pull let go) came back as a
/// transport failure, so the screen it returned to opened on an error. And the first read after
/// the app comes back from the background often dies on a connection iOS closed meanwhile
/// (`networkConnectionLost`): asked again a moment later, it answers.
///
/// So a cancellation is thrown as `CancellationError`, which stores read as nothing, and a read
/// (GET) that fails in transit is asked twice more before it is said. A read that timed out is
/// not: it already waited its minute. A write is not repeated here: `SharpitRetry` owns that,
/// with the screen already showing the change.
nonisolated extension URLSession {
    /// The tries a read gets: the first, then two more.
    static let sharpitReadAttempts = 3

    /// 0.4 s, then 1.2 s: long enough for the radio to wake, short enough to stay a loading state.
    static func sharpitReadPause(beforeRetry retry: Int) -> Duration {
        .milliseconds(retry == 1 ? 400 : 1200)
    }

    func sharpitData(
        for request: URLRequest,
        sleep: (Duration) async throws -> Void = SharpitRetry.defaultSleep
    ) async throws -> (Data, URLResponse) {
        let isRead = (request.httpMethod ?? "GET").uppercased() == "GET"
        var retry = 0
        while true {
            do {
                return try await data(for: request)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    throw CancellationError()
                }
                retry += 1
                let timedOut = (error as? URLError)?.code == .timedOut
                guard isRead, !timedOut, retry < Self.sharpitReadAttempts else { throw SharpitAPIError.transport }
                try await sleep(Self.sharpitReadPause(beforeRetry: retry))
            }
        }
    }
}
