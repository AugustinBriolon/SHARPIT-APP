import Foundation

/// CDN media for the exercises-dataset catalog (same IDs / aliases as the web app).
enum ExerciseMediaCatalog {
    static let attribution = String(localized: "© Gym visual — gymvisual.com")

    private static let cdnRoot = "https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@main"

    private struct Index: Decodable {
        var media: [String: String]
        var names: [String: String]
        var aliases: [String: String]
    }

    private static let index: Index = {
        guard
            let url = indexURL(),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Index.self, from: data)
        else {
            return Index(media: [:], names: [:], aliases: [:])
        }
        return decoded
    }()

    private static func indexURL() -> URL? {
        if let url = Bundle.main.url(forResource: "exercises-media-index", withExtension: "json") {
            return url
        }
        return Bundle.allBundles.lazy
            .compactMap { $0.url(forResource: "exercises-media-index", withExtension: "json") }
            .first
    }

    /// Prefer a persisted catalog id; otherwise match the French/English label like the web resolver.
    static func resolveCatalogId(catalogId: String? = nil, name: String? = nil) -> String? {
        if let catalogId, !catalogId.isEmpty, index.media[catalogId] != nil {
            return catalogId
        }
        guard let name, !name.isEmpty else { return nil }
        let key = normalize(name)
        if key.isEmpty { return nil }
        if let id = index.aliases[key] ?? index.names[key], index.media[id] != nil {
            return id
        }
        // Strip a leading "exercise type " (Garmin-ish labels).
        if key.hasPrefix("exercise type ") {
            let stripped = String(key.dropFirst("exercise type ".count))
            if let id = index.aliases[stripped] ?? index.names[stripped], index.media[id] != nil {
                return id
            }
        }
        return nil
    }

    static func gifURL(catalogId: String? = nil, name: String? = nil) -> URL? {
        guard let id = resolveCatalogId(catalogId: catalogId, name: name),
              let mediaId = index.media[id]
        else { return nil }
        return URL(string: "\(cdnRoot)/videos/\(id)-\(mediaId).gif")
    }

    static func thumbURL(catalogId: String? = nil, name: String? = nil) -> URL? {
        guard let id = resolveCatalogId(catalogId: catalogId, name: name),
              let mediaId = index.media[id]
        else { return nil }
        return URL(string: "\(cdnRoot)/images/\(id)-\(mediaId).jpg")
    }

    /// Same normalization as `@sharpit/app/lib/exercises/normalize`.
    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var scaled = ""
        scaled.reserveCapacity(folded.count)
        for ch in folded.lowercased() {
            if ch == "_" || ch == "/" || ch == "-" {
                scaled.append(" ")
            } else if ch.isLetter || ch.isNumber || ch == " " {
                scaled.append(ch)
            } else {
                scaled.append(" ")
            }
        }
        return scaled.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
