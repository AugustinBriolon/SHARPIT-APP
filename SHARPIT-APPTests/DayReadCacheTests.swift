import Foundation
import Testing
@testable import Sharpit

private nonisolated final class CountingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hits = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.hits += 1
        let day = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "trainingDayId" }?.value ?? ""
        let body = Data(#"{"trainingDayId":"\#(day)","days":[],"weeks":[]}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct DayReadCacheTests {
    private let cache = DayReadCache(today: { "2026-10-17" })

    private func client() -> SharpitClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingURLProtocol.self]
        return SharpitClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://sharpit.app")!,
            dayReads: cache
        )
    }

    @Test func aPastDayIsAskedForOnce() async throws {
        CountingURLProtocol.hits = 0
        let client = client()
        _ = try await client.trainingLoad(trainingDayId: "2026-10-12", token: "t")
        let again = try await client.trainingLoad(trainingDayId: "2026-10-12", token: "t")
        #expect(again.trainingDayId == "2026-10-12")
        #expect(CountingURLProtocol.hits == 1)
    }

    @Test func todayIsAlwaysAskedFor() async throws {
        CountingURLProtocol.hits = 0
        let client = client()
        _ = try await client.trainingLoad(trainingDayId: "2026-10-17", token: "t")
        _ = try await client.trainingLoad(trainingDayId: "2026-10-17", token: "t")
        #expect(CountingURLProtocol.hits == 2)
    }

    @Test func aWriteMakesPastDaysStaleButStillKnown() async throws {
        CountingURLProtocol.hits = 0
        let client = client()
        _ = try await client.trainingLoad(trainingDayId: "2026-10-12", token: "t")
        _ = try? await client.sync(token: "t")
        #expect(cache.lastKnown(V1TrainingLoad.self, day: "2026-10-12") != nil)
        _ = try await client.trainingLoad(trainingDayId: "2026-10-12", token: "t")
        #expect(CountingURLProtocol.hits == 3)
    }

    @Test func todayIsKnownForTheNextScreenButNeverSettled() {
        cache.keep(1, day: "2026-10-17")
        #expect(cache.settled(Int.self, day: "2026-10-17") == nil)
        #expect(cache.lastKnown(Int.self, day: "2026-10-17") == 1)
    }

    @Test func expiringADayKeepsTheOthersFresh() {
        cache.keep(1, day: "2026-10-12")
        cache.keep(2, day: "2026-10-11")
        cache.expire(day: "2026-10-12")
        #expect(cache.settled(Int.self, day: "2026-10-12") == nil)
        #expect(cache.lastKnown(Int.self, day: "2026-10-12") == 1)
        #expect(cache.settled(Int.self, day: "2026-10-11") == 2)
    }
}
