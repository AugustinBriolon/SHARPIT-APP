import Foundation

protocol CoachMemoryServing: Sendable {
    func snapshot(token: String) async throws -> CoachMemorySnapshot
    func saveProfileContext(_ context: String, token: String) async throws
    func createEntry(_ input: CreateCoachMemoryInput, token: String) async throws -> CoachMemoryEntry
    func deleteEntry(id: String, token: String) async throws
}

actor CoachMemoryClient: CoachMemoryServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func snapshot(token: String) async throws -> CoachMemorySnapshot {
        let request = makeRequest(path: "/api/coach-memory", method: "GET", token: token)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(CoachMemorySnapshot.self, from: data)
    }

    func saveProfileContext(_ context: String, token: String) async throws {
        var request = makeRequest(path: "/api/coach/context", method: "PUT", token: token)
        let body = ["context": context]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    func createEntry(_ input: CreateCoachMemoryInput, token: String) async throws -> CoachMemoryEntry {
        var request = makeRequest(path: "/api/coach-memory", method: "POST", token: token)
        request.httpBody = try JSONEncoder().encode(input)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(CoachMemoryEntry.self, from: data) {
            return direct
        }

        struct EntryContainer: Decodable {
            let entry: CoachMemoryEntry
        }
        if let wrapped = try? decoder.decode(EntryContainer.self, from: data) {
            return wrapped.entry
        }

        struct DataContainer: Decodable {
            let data: CoachMemoryEntry
        }
        if let wrappedData = try? decoder.decode(DataContainer.self, from: data) {
            return wrappedData.data
        }

        struct IdContainer: Decodable {
            let id: String?
        }
        let serverId = (try? decoder.decode(IdContainer.self, from: data))?.id ?? UUID().uuidString

        return CoachMemoryEntry(
            id: serverId,
            type: input.type,
            label: input.label,
            locationLabel: input.locationLabel,
            startDate: input.startDate,
            endDate: input.endDate,
            note: input.note,
            trainingConstraint: input.trainingConstraint ?? .full,
            allowedDisciplines: input.allowedDisciplines
        )
    }

    func deleteEntry(id: String, token: String) async throws {
        let request = makeRequest(path: "/api/coach-memory/\(id)", method: "DELETE", token: token)
        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func makeRequest(path: String, method: String, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else {
            throw SharpitAPIError.server
        }
    }
}
