import Foundation
import Testing
@testable import Sharpit

private nonisolated let calendarsFixtureJSON = """
[
  {
    "id": "primary@gmail.com",
    "summary": "Mon agenda",
    "primary": true,
    "backgroundColor": "#9fe1e7",
    "hidden": false,
    "isTarget": true
  },
  {
    "id": "work@group.calendar.google.com",
    "summary": "Travail",
    "primary": false,
    "hidden": true,
    "isTarget": false
  }
]
"""

@Test func googleCalendarsFixtureDecodesWithExtraFieldsIgnored() throws {
    let calendars = try JSONDecoder().decode(
        [V1GoogleCalendar].self,
        from: Data(calendarsFixtureJSON.utf8)
    )
    #expect(calendars.count == 2)
    #expect(calendars[0].id == "primary@gmail.com")
    #expect(calendars[0].summary == "Mon agenda")
    #expect(calendars[0].primary)
    #expect(calendars[0].isTarget)
    #expect(calendars[1].isTarget == false)
}

@Test func anEmptyCalendarListDecodesWhenGoogleIsNotConnected() throws {
    let calendars = try JSONDecoder().decode([V1GoogleCalendar].self, from: Data("[]".utf8))
    #expect(calendars.isEmpty)
}

@Test func googleReconnectErrorBodyDecodesNeedsReconnectFlag() throws {
    let body = try JSONDecoder().decode(
        V1GoogleAPIError.self,
        from: Data(#"{"error":"Relie Google Agenda.","needsReconnect":true}"#.utf8)
    )
    #expect(body.needsReconnect == true)
    #expect(body.error == "Relie Google Agenda.")
}

private nonisolated final class GoogleCalendarsStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var transportError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let transportError = Self.transportError {
            client?.urlProtocol(self, didFailWithError: transportError)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct GoogleCalendarsNetworkTests {
    private func session(status: Int, response: String, transportError: Error? = nil) -> URLSession {
        GoogleCalendarsStubURLProtocol.status = status
        GoogleCalendarsStubURLProtocol.responseData = Data(response.utf8)
        GoogleCalendarsStubURLProtocol.lastRequest = nil
        GoogleCalendarsStubURLProtocol.transportError = transportError
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GoogleCalendarsStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private let base = URL(string: "https://api.example.test")!

    @Test func listingCalendarsUsesTheV1Route() async throws {
        let client = GoogleCalendarsClient(session: session(status: 200, response: calendarsFixtureJSON), baseURL: base)
        let calendars = try await client.googleCalendars(token: "tok")
        let request = try #require(GoogleCalendarsStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.test/api/v1/google/calendars")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(calendars.first?.isTarget == true)
    }

    @Test func selectingACalendarPostsTheIdAndName() async throws {
        let client = GoogleCalendarsClient(session: session(status: 200, response: #"{"success":true}"#), baseURL: base)
        try await client.selectGoogleCalendar(calendarId: "cal-1", calendarName: "Sport", token: "tok")
        let request = try #require(GoogleCalendarsStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.example.test/api/v1/google/select-calendar")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["calendarId"] as? String == "cal-1")
        #expect(body?["calendarName"] as? String == "Sport")
    }

    @Test func listingCalendarsSurfacesGoogleNeedsReconnectOn401() async {
        let reconnectJSON = #"{"error":"Session Google expirée.","needsReconnect":true}"#
        let client = GoogleCalendarsClient(session: session(status: 401, response: reconnectJSON), baseURL: base)
        await #expect(throws: SharpitAPIError.googleNeedsReconnect("Session Google expirée.")) {
            _ = try await client.googleCalendars(token: "tok")
        }
    }

    @Test func listingCalendarsStillUsesUnauthorizedWhen401HasNoReconnectFlag() async {
        let client = GoogleCalendarsClient(session: session(status: 401, response: #"{"error":"Unauthorized"}"#), baseURL: base)
        await #expect(throws: SharpitAPIError.unauthorized) {
            _ = try await client.googleCalendars(token: "tok")
        }
    }

    @Test func listingCalendarsMapsURLCancellationToCancellationError() async {
        let client = GoogleCalendarsClient(
            session: session(status: 200, response: "[]", transportError: URLError(.cancelled)),
            baseURL: base
        )
        await #expect(throws: CancellationError.self) {
            _ = try await client.googleCalendars(token: "tok")
        }
    }
}
