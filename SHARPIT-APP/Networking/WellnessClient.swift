import Foundation

nonisolated protocol WellnessServing: Sendable {
    func wellnessCheckin(trainingDayId: String, token: String) async throws -> V1WellnessCheckin
    func submitWellnessCheckin(
        _ entry: V1WellnessEntry,
        trainingDayId: String,
        token: String
    ) async throws
}

actor WellnessClient: WellnessServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func wellnessCheckin(
        trainingDayId: String,
        token: String
    ) async throws -> V1WellnessCheckin {
        guard var components = URLComponents(
            url: baseURL.appending(path: "/api/wellness-checkin"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SharpitAPIError.server
        }
        components.queryItems = [URLQueryItem(name: "trainingDayId", value: trainingDayId)]
        guard let url = components.url else { throw SharpitAPIError.server }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await send(request, accepting: [200])
        do {
            return try JSONDecoder().decode(V1WellnessCheckin.self, from: data)
        } catch {
            throw WellnessClientError.decoding(String(describing: error))
        }
    }

    func submitWellnessCheckin(
        _ entry: V1WellnessEntry,
        trainingDayId: String,
        token: String
    ) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/wellness-checkin"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var payload: [String: Any] = [
            "trainingDayId": trainingDayId,
            "mood": entry.mood,
            "energyLevel": entry.energyLevel,
            "perceivedSoreness": entry.perceivedSoreness,
            "stressLevel": entry.stressLevel
        ]
        payload["notes"] = entry.notes ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // 201 on the first submit of the day, 200 when it replaces one already there.
        _ = try await send(request, accepting: [200, 201])
    }

    private func send(_ request: URLRequest, accepting statuses: Set<Int>) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statuses.contains(status) else {
            if status == 401 { throw SharpitAPIError.unauthorized }
            throw SharpitAPIError.server
        }
        return data
    }
}

enum WellnessClientError: Error, Equatable, LocalizedError {
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .decoding: "Réponse du ressenti incompatible"
        }
    }
}
