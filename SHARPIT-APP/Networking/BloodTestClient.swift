import Foundation

/// One confirmed result, in the web's `postBloodTestSchema` shape (SHARPIT ADR-128).
nonisolated struct BloodTestResultInput: Codable, Equatable, Sendable {
    let markerKey: String
    let value: Double
    let unit: String
    let refLow: Double?
    let refHigh: Double?
}

nonisolated protocol BloodTestWriting: Sendable {
    func createBloodTest(sampledAt: Date, results: [BloodTestResultInput], token: String) async throws
}

/// `/api/v1/blood-tests` — results only. The body has no field for a document or a name, and the
/// server refuses any it does not know.
actor BloodTestClient: BloodTestWriting {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    private struct Body: Encodable {
        let sampledAt: Date
        let results: [BloodTestResultInput]
    }

    func createBloodTest(sampledAt: Date, results: [BloodTestResultInput], token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/blood-tests"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(Body(sampledAt: sampledAt, results: results))
        let (_, response) = try await session.data(for: request)
        try Self.check(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    nonisolated static func check(status: Int) throws {
        switch status {
        case 200...299: return
        case 401: throw SharpitAPIError.unauthorized
        case 403: throw SharpitAPIError.message(String(localized: "Active le consentement santé dans Paramètres pour enregistrer une analyse."))
        case 400...499: throw SharpitAPIError.badRequest
        default: throw SharpitAPIError.server
        }
    }
}
