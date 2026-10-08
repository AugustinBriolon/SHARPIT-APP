import Foundation

/// One Google calendar the athlete can pick as the write/read target — as `/api/v1/google/calendars`
/// returns it (the web's `mapCalendarListItem`). Extra fields such as `hidden` are ignored.
nonisolated struct V1GoogleCalendar: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let summary: String
    let primary: Bool
    let isTarget: Bool
}

/// Error JSON from `/api/v1/google/*` when Google OAuth must be renewed (`needsReconnect: true`, 401).
nonisolated struct V1GoogleAPIError: Decodable, Sendable, Equatable {
    let error: String?
    let needsReconnect: Bool?
}

nonisolated protocol GoogleCalendarsServing: Sendable {
    func googleCalendars(token: String) async throws -> [V1GoogleCalendar]
    func selectGoogleCalendar(calendarId: String, calendarName: String?, token: String) async throws
}

/// `GET /api/v1/google/calendars` and `POST /api/v1/google/select-calendar` — the native contracts
/// for the web's Google calendar handlers (ADR-040).
actor GoogleCalendarsClient: GoogleCalendarsServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func googleCalendars(token: String) async throws -> [V1GoogleCalendar] {
        try await send(path: "/api/v1/google/calendars", method: "GET", token: token) { data in
            try JSONDecoder().decode([V1GoogleCalendar].self, from: data)
        }
    }

    func selectGoogleCalendar(calendarId: String, calendarName: String?, token: String) async throws {
        var payload: [String: Any] = ["calendarId": calendarId]
        if let calendarName { payload["calendarName"] = calendarName }
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await send(path: "/api/v1/google/select-calendar", method: "POST", token: token, body: body) { _ in () }
    }

    private func send<T>(
        path: String,
        method: String,
        token: String,
        body: Data? = nil,
        decode: (Data) throws -> T
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let googleError = try? JSONDecoder().decode(V1GoogleAPIError.self, from: data)
            if status == 401, googleError?.needsReconnect == true {
                let message = googleError?.error
                    ?? "Session Google expirée ou révoquée. Reconnecte Google Calendar dans les paramètres."
                throw SharpitAPIError.googleNeedsReconnect(message)
            }
            if status == 401 || status == 403 { throw SharpitAPIError.unauthorized }
            if status == 429 { throw SharpitAPIError.rateLimited }
            if status >= 500 { throw SharpitAPIError.server }
            if let message = googleError?.error {
                throw SharpitAPIError.message(message)
            }
            throw SharpitAPIError.badRequest
        }

        do {
            return try decode(data)
        } catch {
            throw SharpitAPIError.server
        }
    }
}
