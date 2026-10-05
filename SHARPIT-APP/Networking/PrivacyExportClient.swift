import Foundation

/// The athlete's data, whole, as one JSON file — the GDPR access and portability right
/// (`/api/v1/privacy/export`, the web's `buildAthleteExportJson`: profile, consents, activities,
/// plan, measures; never a credential).
nonisolated protocol PrivacyExporting: Sendable {
    func exportData(token: String) async throws -> Data
}

/// `GET /api/v1/privacy/export`.
actor PrivacyExportClient: PrivacyExporting {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    /// The server builds the file in one go, years of activities included: it may take a while.
    func exportData(token: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/privacy/export"), timeoutInterval: 120)
        request.httpMethod = "GET"
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
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 { throw SharpitAPIError.unauthorized }
            if status == 429 { throw SharpitAPIError.rateLimited }
            throw SharpitAPIError.server
        }
        guard PrivacyExport.isJSONObject(data) else { throw SharpitAPIError.server }
        return data
    }
}

/// Where the export lands on the phone before the share sheet hands it on.
nonisolated enum PrivacyExport {
    /// « sharpit-export-2026-10-05.json »: the day it was taken, never the athlete's id — the
    /// file may be sent anywhere, and its name is read by whoever receives it.
    static func fileName(on date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "sharpit-export-\(day).json"
    }

    /// The server answers a JSON object; anything else (an HTML error page) is not an export.
    static func isJSONObject(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }

    /// Writes the file in its own folder of the temporary directory, replacing an earlier
    /// export of the same day. The system clears the folder; nothing is kept on purpose.
    static func write(_ data: Data, on date: Date = .now, in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let folder = directory.appending(path: "SharpItExport", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: fileName(on: date))
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        return file
    }
}
