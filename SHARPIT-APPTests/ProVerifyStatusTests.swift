import Foundation
import Testing
@testable import Sharpit

private nonisolated final class ProVerifyStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":"x"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ProVerifyStatusTests {
    private func verify(status: Int) async throws -> V1Pro {
        ProVerifyStubURLProtocol.status = status
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProVerifyStubURLProtocol.self]
        let client = ProClient(session: URLSession(configuration: configuration), baseURL: URL(string: "https://api.example.test")!)
        return try await client.verify(signedTransaction: "jws", signedRenewalInfo: nil, token: "tok")
    }

    @Test func aTransactionTheWebCannotVerifyIsABadRequest() async {
        await #expect(throws: SharpitAPIError.badRequest) { try await verify(status: 400) }
    }

    @Test func aPurchaseOwnedByAnotherAccountIsAConflict() async {
        await #expect(throws: SharpitAPIError.conflict) { try await verify(status: 409) }
    }

    @Test func aConflictIsNotTriedAgain() {
        #expect(!SharpitRetry.isTransient(SharpitAPIError.conflict))
    }
}
