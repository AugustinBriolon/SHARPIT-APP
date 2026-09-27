import Foundation

/// A pain or an injury to record, in the web's `createPhysicalNoteSchema` shape.
nonisolated struct CreatePhysicalNoteInput: Codable, Equatable, Sendable {
    /// `PAIN` or `INJURY` (the web's `PhysicalCategory`).
    let category: String
    let title: String
    let bodyPart: String
    /// `LEFT`, `RIGHT`, `BILATERAL` or `NA`.
    let side: String
    /// 0…10.
    let severity: Int
    /// Injected into the coach's context, so plans work around it.
    let affectsTraining: Bool
}

nonisolated protocol PhysicalNoteCreating: Sendable {
    func createNote(_ input: CreatePhysicalNoteInput, token: String) async throws
}

/// `/api/v1/physical-notes` — the web's physical-health notes, which the coach reads as
/// sensitive zones when it plans.
actor PhysicalNoteClient: PhysicalNoteCreating {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func createNote(_ input: CreatePhysicalNoteInput, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/physical-notes"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(input)

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
    }
}
