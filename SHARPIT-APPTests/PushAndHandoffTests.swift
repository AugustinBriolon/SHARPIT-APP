import Foundation
import Testing
@testable import Sharpit

// MARK: - Stub URLProtocol for Push Tests

private nonisolated final class PushStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var responseData = Data("{\"ok\":true}".utf8)
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makePushClient() -> SharpitClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PushStubURLProtocol.self]
    return SharpitClient(
        session: URLSession(configuration: configuration),
        baseURL: URL(string: "https://sharpit.app")!
    )
}

// MARK: - Mock PushDeviceTokenServing

private final class MockPushService: PushDeviceTokenServing, @unchecked Sendable {
    var registeredToken: String?
    var registeredDebug: Bool?
    var registeredAuthToken: String?
    var unregisterCalled: Bool = false

    func registerDeviceToken(_ deviceToken: String, debug: Bool, token: String) async throws {
        self.registeredToken = deviceToken
        self.registeredDebug = debug
        self.registeredAuthToken = token
    }

    func unregisterDeviceToken(_ deviceToken: String, token: String) async throws {
        self.unregisterCalled = true
    }
}

// MARK: - Push & Handoff Test Suite

@Suite(.serialized)
struct PushAndHandoffTests {

    @Test func deviceTokenHexEncoding() {
        let manager = PushNotificationManager()
        let sampleData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x23, 0x45, 0x67])
        manager.didRegisterForRemoteNotifications(with: sampleData)
        #expect(manager.deviceToken == "deadbeef01234567")
    }

    @Test func morningVerdictPushNotificationRoutingByCategory() {
        let manager = PushNotificationManager()
        manager.didReceiveNotificationResponse(userInfo: ["category": "MORNING_VERDICT"])
        #expect(manager.pendingDestination == .tab(.today))
        #expect(manager.consumePendingDestination() == .tab(.today))
        #expect(manager.pendingDestination == nil)
    }

    @Test func morningVerdictPushNotificationRoutingByApsCategory() {
        #expect(PushNotificationManager.destination(for: ["aps": ["category": "MORNING_VERDICT"]]) == .tab(.today))
    }

    @Test func morningVerdictPushNotificationRoutingByThreadId() {
        #expect(PushNotificationManager.destination(for: ["aps": ["thread-id": "morning-verdict"]]) == .tab(.today))
    }

    /// Every push the server sends, and the session reminder, lands where it speaks of.
    @Test func eachNotificationOpensWhatItSpeaksOf() {
        #expect(PushNotificationManager.destination(for: ["url": "/plan/generator"]) == .planGenerator)
        #expect(PushNotificationManager.destination(for: ["url": "/plan/review"]) == .weeklyReview)
        #expect(PushNotificationManager.destination(for: ["url": "/settings/sources"]) == .settings(.sources))
        #expect(PushNotificationManager.destination(for: ["url": "/settings"]) == .settings(nil))
        #expect(PushNotificationManager.destination(for: ["url": "/plan"]) == .tab(.plan))
        #expect(PushNotificationManager.destination(for: ["url": "https://sharpit.app/today"]) == .tab(.today))
        #expect(PushNotificationManager.destination(for: [:]) == nil)
    }

    /// « Séance comptée » opens the activity that counted.
    @Test func aCountedSessionOpensItsActivity() {
        #expect(PushNotificationManager.destination(for: ["url": "/activity/act-1"]) == .activity(id: "act-1"))
        #expect(PushNotificationManager.destination(for: ["url": "https://sharpit.app/activity/act-1"]) == .activity(id: "act-1"))
        // No id: the Activité tab, as a bare `/activity` link.
        #expect(PushNotificationManager.destination(for: ["url": "/activity/"]) == .tab(.activity))
    }

    @Test func theCountedSessionPushIsOnUntilSwitchedOff() throws {
        let absent = try JSONDecoder().decode(V1NotificationPrefs.self, from: Data(#"{"version":1}"#.utf8))
        let off = try JSONDecoder().decode(V1NotificationPrefs.self, from: Data(#"{"version":1,"sessionDone":false}"#.utf8))
        #expect(absent.sessionDone)
        #expect(!off.sessionDone)
    }

    @Test func pushNotificationRoutingByUrl() {
        let manager = PushNotificationManager()

        manager.didReceiveNotificationResponse(userInfo: ["url": "https://sharpit.app/plan"])
        #expect(manager.consumePendingDestination() == .tab(.plan))

        manager.didReceiveNotificationResponse(userInfo: ["url": "https://sharpit.app/coach"])
        #expect(manager.consumePendingDestination() == .tab(.coach))

        manager.didReceiveNotificationResponse(userInfo: ["url": "https://sharpit.app/activity"])
        #expect(manager.consumePendingDestination() == .tab(.activity))

        manager.didReceiveNotificationResponse(userInfo: ["url": "https://sharpit.app/me"])
        #expect(manager.consumePendingDestination() == .tab(.body))

        manager.didReceiveNotificationResponse(userInfo: ["url": "https://sharpit.app/corps"])
        #expect(manager.consumePendingDestination() == .tab(.body))
    }

    @Test func syncDeviceTokenFlow() async {
        let manager = PushNotificationManager()
        let mockService = MockPushService()

        // Without token, does nothing
        await manager.syncDeviceTokenIfNeeded(tokenProvider: { "auth-tok" }, client: mockService)
        #expect(mockService.registeredToken == nil)

        // Set token
        manager.deviceToken = "device-abc"
        await manager.syncDeviceTokenIfNeeded(tokenProvider: { "auth-tok" }, client: mockService)
        #expect(mockService.registeredToken == "device-abc")
        #expect(mockService.registeredAuthToken == "auth-tok")
        #expect(manager.lastRegisteredToken == "device-abc")

        // Calling again does not re-register identical token
        mockService.registeredToken = nil
        await manager.syncDeviceTokenIfNeeded(tokenProvider: { "auth-tok" }, client: mockService)
        #expect(mockService.registeredToken == nil)
    }

    @Test func switchingNotificationsOffForgetsTheDevice() async throws {
        let defaults = try #require(UserDefaults(suiteName: "push-switch"))
        defaults.removePersistentDomain(forName: "push-switch")
        let manager = PushNotificationManager(defaults: defaults)
        let mockService = MockPushService()
        manager.deviceToken = "device-xyz"
        await manager.syncDeviceTokenIfNeeded(tokenProvider: { "auth-tok" }, client: mockService)
        #expect(manager.lastRegisteredToken == "device-xyz")

        await manager.setEnabled(false, tokenProvider: { "auth-tok" }, client: mockService)
        #expect(mockService.unregisterCalled)
        #expect(!manager.isEnabledByAthlete)
        #expect(manager.lastRegisteredToken == nil)

        // Switched off, a new launch registers nothing.
        mockService.registeredToken = nil
        let relaunched = PushNotificationManager(defaults: defaults)
        relaunched.deviceToken = "device-xyz"
        await relaunched.syncDeviceTokenIfNeeded(tokenProvider: { "auth-tok" }, client: mockService)
        #expect(mockService.registeredToken == nil)
    }

    @Test func sharpitClientRegisterDeviceTokenEndpoint() async throws {
        PushStubURLProtocol.status = 200
        PushStubURLProtocol.lastRequest = nil
        PushStubURLProtocol.lastBody = nil

        let client = makePushClient()
        try await client.registerDeviceToken("test-tok-123", debug: true, token: "jwt-token")

        let req = try #require(PushStubURLProtocol.lastRequest)
        #expect(req.url?.path == "/api/v1/push/device-token")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token")

        let bodyData = try #require(PushStubURLProtocol.lastBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        #expect(json?["token"] as? String == "test-tok-123")
        #expect(json?["platform"] as? String == "ios")
        #expect(json?["bundleId"] as? String == "app.sharpit.ios")
        #expect(json?["debug"] as? Bool == true)
    }

    @Test func sharpitClientUnregisterDeviceTokenEndpoint() async throws {
        PushStubURLProtocol.status = 200
        PushStubURLProtocol.lastRequest = nil
        PushStubURLProtocol.lastBody = nil

        let client = makePushClient()
        try await client.unregisterDeviceToken("test-tok-456", token: "jwt-token")

        let req = try #require(PushStubURLProtocol.lastRequest)
        #expect(req.url?.path == "/api/v1/push/device-token")
        #expect(req.httpMethod == "DELETE")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token")

        let bodyData = try #require(PushStubURLProtocol.lastBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        #expect(json?["token"] as? String == "test-tok-456")
    }
}
