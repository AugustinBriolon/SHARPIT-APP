import Foundation

/// What the server answers once a session is on the athlete's Garmin calendar.
nonisolated struct V1GarminWorkoutReceipt: Decodable, Sendable, Equatable {
    let workoutId: String
    /// "yyyy-MM-dd", the day the watch will offer it.
    let scheduledDate: String
    /// Targets sent without guidance, in the athlete's words (an FTP unknown, say).
    let warnings: [String]
    /// True when the session had no written steps and one was derived from its length.
    let derived: Bool
}

/// Sends a planned session to the athlete's watch (SHARPIT ADR-106). A protocol so the drawer
/// can be tested without the network.
protocol GarminWorkoutPushing: Sendable {
    /// `replace` deletes the workout sent before and sends the session again.
    func sendToWatch(plannedSessionId: String, replace: Bool, token: String) async throws -> V1GarminWorkoutReceipt
}

actor GarminWorkoutClient: GarminWorkoutPushing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func sendToWatch(plannedSessionId: String, replace: Bool, token: String) async throws -> V1GarminWorkoutReceipt {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/garmin/workouts/from-planned-session"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "plannedSessionId": plannedSessionId,
            "replace": replace,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200...299).contains(status) {
            guard let receipt = try? JSONDecoder().decode(V1GarminWorkoutReceipt.self, from: data) else {
                throw SharpitAPIError.server
            }
            return receipt
        }
        throw Self.error(status: status, body: data)
    }

    /// A Garmin refusal (no permission, Garmin session lost, quota) is a 403 or a 429 carrying
    /// the server's words: said as they are, never read as the SharpIt session gone.
    nonisolated static func error(status: Int, body: Data) -> SharpitAPIError {
        if status == 401 { return .unauthorized }
        if status == 403, SharpitAPIError.isProRequired(body) { return .proRequired }
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        if let message = json?["error"] as? String, !message.isEmpty { return .message(message) }
        return status == 429 ? .rateLimited : .server
    }
}
