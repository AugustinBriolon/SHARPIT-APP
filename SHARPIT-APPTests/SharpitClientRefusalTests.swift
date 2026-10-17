import Foundation
import Testing
@testable import Sharpit

private nonisolated final class RefusalStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 403
    nonisolated(unsafe) static var body = Data(#"{"code":"CONSENT_REQUIRED"}"#.utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct SharpitClientRefusalTests {
    private func makeClient() -> SharpitClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusalStubURLProtocol.self]
        return SharpitClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://stub.sharpit.test")!,
            dayReads: DayReadCache()
        )
    }

    /// A 403 is a refusal for this athlete (consents owed, Pro, a quota) — never a session gone.
    /// Signing out on it logged a new account out in the middle of its onboarding.
    @MainActor
    @Test func aForbiddenReadNeverSignsTheAthleteOut() async {
        AuthSession.shared.resetForTests()
        var refreshes = 0
        var signedOut = 0
        AuthSession.shared.refreshToken = { refreshes += 1; return "fresh" }
        AuthSession.shared.performSignOut = { signedOut += 1 }

        await #expect(throws: SharpitAPIError.self) {
            _ = try await makeClient().today(trainingDayId: "2026-10-17", token: "t")
        }

        #expect(refreshes == 0)
        #expect(signedOut == 0)
        #expect(!AuthSession.shared.expiredNotice)
        AuthSession.shared.resetForTests()
    }
}
