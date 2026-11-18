import Foundation
import Testing
@testable import Sharpit

/// Fails the first `failures` requests with `error`, then answers 200.
private nonisolated final class FlakyURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hits = 0
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var error = URLError(.networkConnectionLost)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.hits += 1
        if Self.hits <= Self.failures {
            client?.urlProtocol(self, didFailWithError: Self.error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct SharpitTransportTests {
    private func session(failing failures: Int, with error: URLError = URLError(.networkConnectionLost)) -> URLSession {
        FlakyURLProtocol.hits = 0
        FlakyURLProtocol.failures = failures
        FlakyURLProtocol.error = error
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlakyURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func request(_ method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://sharpit.app/api/v1/today")!)
        request.httpMethod = method
        return request
    }

    /// The first read after the app comes back often dies on a connection iOS closed.
    @Test func aReadDroppedInTransitIsAskedAgain() async throws {
        let session = session(failing: 2)
        let (data, _) = try await session.sharpitData(for: request("GET"), sleep: { _ in })
        #expect(data == Data("{}".utf8))
        #expect(FlakyURLProtocol.hits == 3)
    }

    @Test func aReadThatKeepsFailingIsATransportFailure() async {
        let session = session(failing: 10)
        await #expect(throws: SharpitAPIError.transport) {
            _ = try await session.sharpitData(for: request("GET"), sleep: { _ in })
        }
        #expect(FlakyURLProtocol.hits == URLSession.sharpitReadAttempts)
    }

    /// `SharpitRetry` owns a write's retries: sent twice here, it could be applied twice.
    @Test func aWriteIsSentOnce() async {
        let session = session(failing: 1)
        await #expect(throws: SharpitAPIError.transport) {
            _ = try await session.sharpitData(for: request("POST"), sleep: { _ in })
        }
        #expect(FlakyURLProtocol.hits == 1)
    }

    /// A screen left mid-read is not a network failure.
    @Test func aCancelledRequestIsACancellationNotAnOutage() async {
        let session = session(failing: 1, with: URLError(.cancelled))
        await #expect(throws: CancellationError.self) {
            _ = try await session.sharpitData(for: request("GET"), sleep: { _ in })
        }
        #expect(FlakyURLProtocol.hits == 1)
    }

    @Test func aReadThatTimedOutIsNotAskedAgain() async {
        let session = session(failing: 1, with: URLError(.timedOut))
        await #expect(throws: SharpitAPIError.transport) {
            _ = try await session.sharpitData(for: request("GET"), sleep: { _ in })
        }
        #expect(FlakyURLProtocol.hits == 1)
    }
}
