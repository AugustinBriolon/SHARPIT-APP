import Foundation

nonisolated protocol JournalServing: Sendable {
    func dayJournal(trainingDayId: String, token: String) async throws -> V1DayJournalEntry
    func saveDayJournal(_ entry: V1DayJournalEntry, token: String) async throws -> V1DayJournalEntry
    func journalDaySignals(trainingDayId: String, token: String) async throws -> V1JournalDaySignals
    func journalPrefs(token: String) async throws -> (prefs: JournalPrefs, isPro: Bool)
    func saveJournalPrefs(
        _ prefs: JournalPrefs,
        token: String
    ) async throws -> (prefs: JournalPrefs, isPro: Bool)
}

actor JournalClient: JournalServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func dayJournal(trainingDayId: String, token: String) async throws -> V1DayJournalEntry {
        guard var components = URLComponents(
            url: baseURL.appending(path: "/api/v1/day-journal"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        components.queryItems = [URLQueryItem(name: "day", value: trainingDayId)]
        guard let url = components.url else { throw SharpitAPIError.server }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await send(request)
        let envelope = try decode(V1DayJournalEnvelope.self, from: data)
        var entry = envelope.entry ?? V1DayJournalEntry(trainingDayId: trainingDayId)
        // A day with nothing recorded comes back without its own id.
        entry.trainingDayId = trainingDayId
        return entry
    }

    func saveDayJournal(
        _ entry: V1DayJournalEntry,
        token: String
    ) async throws -> V1DayJournalEntry {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/day-journal"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(entry)

        let data = try await send(request)
        let envelope = try decode(V1DayJournalEnvelope.self, from: data)
        var saved = envelope.entry ?? entry
        saved.trainingDayId = entry.trainingDayId
        return saved
    }

    /// The derived half of the day: the automatic checklist, decided server-side.
    ///
    /// Same `day=` parameter as `dayJournal` above, because it answers about the same day.
    /// Note the rest of the app sends `trainingDayId` instead — these two journal routes are
    /// web-internal and predate that convention.
    func journalDaySignals(
        trainingDayId: String,
        token: String
    ) async throws -> V1JournalDaySignals {
        guard var components = URLComponents(
            url: baseURL.appending(path: "/api/v1/journal/day-signals"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        components.queryItems = [URLQueryItem(name: "day", value: trainingDayId)]
        guard let url = components.url else { throw SharpitAPIError.server }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var signals = try decode(V1JournalDaySignals.self, from: try await send(request))
        // A day with nothing derived comes back without its own id, as the entry does.
        signals.trainingDayId = trainingDayId
        return signals
    }

    func journalPrefs(token: String) async throws -> (prefs: JournalPrefs, isPro: Bool) {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/journal-prefs"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try prefs(from: try await send(request))
    }

    func saveJournalPrefs(
        _ prefs: JournalPrefs,
        token: String
    ) async throws -> (prefs: JournalPrefs, isPro: Bool) {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/journal-prefs"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["prefs": prefs.raw.mapValues(\.foundationObject)]
        )
        return try self.prefs(from: try await send(request))
    }

    private func prefs(from data: Data) throws -> (prefs: JournalPrefs, isPro: Bool) {
        let envelope = try decode(V1JournalPrefsEnvelope.self, from: data)
        guard case .object(let raw)? = envelope.prefs else {
            return (.empty, envelope.isPro == true)
        }
        return (JournalPrefs(raw: raw), envelope.isPro == true)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 { throw SharpitAPIError.unauthorized }
            throw SharpitAPIError.server
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw JournalClientError.decoding(String(describing: error))
        }
    }
}

enum JournalClientError: Error, Equatable, LocalizedError {
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .decoding: "Réponse du journal incompatible"
        }
    }
}
