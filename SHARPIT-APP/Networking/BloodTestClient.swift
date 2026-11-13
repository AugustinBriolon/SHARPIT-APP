import Foundation

/// One confirmed result, in the web's `postBloodTestSchema` shape (SHARPIT ADR-128).
nonisolated struct BloodTestResultInput: Codable, Equatable, Sendable {
    let markerKey: String
    let value: Double
    let unit: String
    let refLow: Double?
    let refHigh: Double?
}

/// A stored blood test as `GET /api/v1/blood-tests` returns it: the sampling time and the results,
/// nothing of the document.
nonisolated struct V1BloodTest: Decodable, Identifiable, Equatable, Sendable {
    struct Result: Decodable, Equatable, Sendable {
        let markerKey: String
        let value: Double
        let unit: String
        let refLow: Double?
        let refHigh: Double?

        var marker: BloodMarker? { BloodMarkerCatalog.marker(markerKey) }
        var status: BloodMarkerStatus { BloodMarkerStatus(value: value, refLow: refLow, refHigh: refHigh) }
    }

    let id: String
    let sampledAt: Date
    let results: [Result]

    private enum CodingKeys: String, CodingKey {
        case id, sampledAt, results
    }

    init(id: String, sampledAt: Date, results: [Result]) {
        self.id = id
        self.sampledAt = sampledAt
        self.results = results
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        results = try container.decode([Result].self, forKey: .results)
        let text = try container.decode(String.self, forKey: .sampledAt)
        guard let date = APIDate.instant(text) else {
            throw DecodingError.dataCorruptedError(forKey: .sampledAt, in: container, debugDescription: "Not an instant")
        }
        sampledAt = date
    }

    /// Results outside the lab's own bounds.
    var outOfRangeCount: Int {
        results.count { $0.status == .low || $0.status == .high }
    }
}

/// What `GET /api/v1/blood-tests/{id}/reading` answers (SHARPIT ADR-129): the sessions before the
/// sample and the sourced findings. The server computes it; the app only shows it.
nonisolated struct V1BloodTestReading: Decodable, Equatable, Sendable {
    struct Training: Decodable, Equatable, Sendable {
        let sessionsInWeek: Int
        let strengthInWeek: Int
        let sessionsInFourWeeks: Int
    }

    struct Finding: Decodable, Equatable, Sendable {
        enum Tone: String, Decodable, Sendable {
            case context, doctor
        }

        let key: String
        let markerKeys: [String]
        let tone: Tone
        let text: String
        let source: String
    }

    let training: Training
    let findings: [Finding]
}

nonisolated protocol BloodTestReading: Sendable {
    /// Throws `SharpitAPIError.proRequired` below Pro.
    func reading(testId: String, token: String) async throws -> V1BloodTestReading
}

nonisolated protocol BloodTestWriting: Sendable {
    func createBloodTest(sampledAt: Date, results: [BloodTestResultInput], token: String) async throws
}

nonisolated protocol BloodTestServing: Sendable {
    /// Every test of the athlete, latest sampling first.
    func bloodTests(token: String) async throws -> [V1BloodTest]
    func deleteBloodTest(id: String, token: String) async throws
}

/// `/api/v1/blood-tests` — results only. The body has no field for a document or a name, and the
/// server refuses any it does not know.
actor BloodTestClient: BloodTestWriting, BloodTestServing, BloodTestReading {
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

    private struct ListBody: Decodable {
        let bloodTests: [V1BloodTest]
    }

    func createBloodTest(sampledAt: Date, results: [BloodTestResultInput], token: String) async throws {
        var request = request(path: "/api/v1/blood-tests", method: "POST", token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(Body(sampledAt: sampledAt, results: results))
        let (_, response) = try await session.data(for: request)
        try Self.check(status: Self.status(response))
    }

    func bloodTests(token: String) async throws -> [V1BloodTest] {
        let (data, response) = try await session.data(for: request(path: "/api/v1/blood-tests", method: "GET", token: token))
        try Self.check(status: Self.status(response))
        return try JSONDecoder().decode(ListBody.self, from: data).bloodTests
    }

    func reading(testId: String, token: String) async throws -> V1BloodTestReading {
        let (data, response) = try await session.data(
            for: request(path: "/api/v1/blood-tests/\(testId)/reading", method: "GET", token: token)
        )
        let status = Self.status(response)
        if status == 403, SharpitAPIError.isProRequired(data) { throw SharpitAPIError.proRequired }
        try Self.check(status: status)
        return try JSONDecoder().decode(V1BloodTestReading.self, from: data)
    }

    func deleteBloodTest(id: String, token: String) async throws {
        let (_, response) = try await session.data(for: request(path: "/api/v1/blood-tests/\(id)", method: "DELETE", token: token))
        let status = Self.status(response)
        // Already gone is what the athlete asked for.
        if status == 404 { return }
        try Self.check(status: status)
    }

    private func request(path: String, method: String, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func status(_ response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? 0
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
