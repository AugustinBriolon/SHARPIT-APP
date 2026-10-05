import Foundation

/// A zone to declare, in the web's `createPhysicalNoteSchema` shape.
nonisolated struct CreatePhysicalNoteInput: Codable, Equatable, Sendable {
    /// `PAIN`, `INJURY`, `MOBILITY`, `POSTURE` or `OTHER` (the web's `PhysicalCategory`).
    let category: String
    let title: String
    let bodyPart: String
    /// `LEFT`, `RIGHT`, `BILATERAL` or `NA`.
    let side: String
    /// 0…10.
    let severity: Int
    /// Injected into the coach's context, so plans work around it.
    let affectsTraining: Bool
    /// `NONE` … `STOPPED` — what the athlete can still do (SHARPIT ADR-068).
    var functionalImpact: String? = nil
    var description: String? = nil
}

/// What changes on a declared zone; only the fields set are sent.
nonisolated struct PhysicalNotePatch: Encodable, Equatable, Sendable {
    var category: String?
    var title: String?
    var bodyPart: String?
    var side: String?
    var severity: Int?
    var description: String?
    var affectsTraining: Bool?
    /// `ACTIVE`, `MONITORING` or `RESOLVED` — the web records the change on the zone's timeline.
    var status: String?
    var functionalImpact: String?
}

/// One follow-up on a zone: how much it hurts, and what the athlete could still do.
nonisolated struct PhysicalCheckinInput: Encodable, Equatable, Sendable {
    let severity: Int
    let functionalImpact: String?
    let comment: String?
}

nonisolated protocol PhysicalNoteCreating: Sendable {
    func createNote(_ input: CreatePhysicalNoteInput, token: String) async throws
}

/// The zones page: read them whole, change one, follow one up.
nonisolated protocol SensitiveZoneServing: PhysicalNoteCreating {
    /// `/api/v1/sensitive-zones` as sent, so the page can keep it and paint it offline.
    func sensitiveZonesData(token: String) async throws -> Data
    func updateNote(id: String, patch: PhysicalNotePatch, token: String) async throws
    func addCheckin(noteId: String, input: PhysicalCheckinInput, token: String) async throws
}

/// `/api/v1/physical-notes` and `/api/v1/sensitive-zones` — the athlete's declared zones, which
/// the coach reads when it plans.
actor PhysicalNoteClient: SensitiveZoneServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func createNote(_ input: CreatePhysicalNoteInput, token: String) async throws {
        _ = try await send("/api/v1/physical-notes", method: "POST", body: input, token: token)
    }

    func sensitiveZonesData(token: String) async throws -> Data {
        try await send("/api/v1/sensitive-zones", method: "GET", body: nil as String?, token: token)
    }

    func updateNote(id: String, patch: PhysicalNotePatch, token: String) async throws {
        _ = try await send("/api/v1/physical-notes/\(id)", method: "PATCH", body: patch, token: token)
    }

    func addCheckin(noteId: String, input: PhysicalCheckinInput, token: String) async throws {
        _ = try await send("/api/v1/physical-notes/\(noteId)/checkins", method: "POST", body: input, token: token)
    }

    private func send<Body: Encodable>(_ path: String, method: String, body: Body?, token: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
        return data
    }
}
