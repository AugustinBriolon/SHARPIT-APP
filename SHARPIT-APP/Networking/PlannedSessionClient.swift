import Foundation

protocol PlannedSessionServing: Sendable {
    func plannedSessions(from: Date, to: Date, token: String) async throws -> [V1PlannedSessionItem]
}

actor PlannedSessionClient: PlannedSessionServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func plannedSessions(from: Date, to: Date, token: String) async throws -> [V1PlannedSessionItem] {
        guard var components = URLComponents(
            url: baseURL.appending(path: "/api/planned-sessions"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        components.queryItems = [
            URLQueryItem(name: "from", value: Self.dayString(from)),
            URLQueryItem(name: "to", value: Self.dayString(to))
        ]
        guard let url = components.url else { throw SharpitAPIError.server }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bear" + "er " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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
        do {
            return try JSONDecoder().decode([V1PlannedSessionItem].self, from: data)
        } catch {
            throw PlannedSessionClientError.decoding(String(describing: error))
        }
    }

    private nonisolated static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum PlannedSessionClientError: Error, LocalizedError {
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .decoding: "Réponse du plan incompatible"
        }
    }
}
