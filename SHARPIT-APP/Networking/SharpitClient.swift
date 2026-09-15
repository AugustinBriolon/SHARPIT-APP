import Foundation

actor SharpitClient: TodayServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "/api/v1/today"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "trainingDayId", value: trainingDayId)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            break
        case 400:
            throw SharpitAPIError.badRequest
        case 401:
            throw SharpitAPIError.unauthorized
        default:
            throw SharpitAPIError.server
        }

        do {
            return try JSONDecoder().decode(V1TodayResponse.self, from: data)
        } catch {
            throw SharpitAPIError.server
        }
    }
}
