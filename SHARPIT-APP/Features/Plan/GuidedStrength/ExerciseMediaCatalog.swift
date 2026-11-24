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

    /// An exercise the catalog knows, as the search lists it.
    struct Entry: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
    }

    /// The catalog's exercises whose name holds every word typed, French aliases first, one
    /// line per exercise. Empty for an empty query: the catalog is searched, not browsed.
    static func search(_ query: String, limit: Int = 30) -> [Entry] {
        let words = normalize(query).split(separator: " ")
        guard !words.isEmpty else { return [] }
        var seen = Set<String>()
        var found: [Entry] = []
        for source in [index.aliases, index.names] {
            for (name, id) in source.sorted(by: { $0.key < $1.key }) where !seen.contains(id) {
                guard words.allSatisfy({ name.contains($0) }) else { continue }
                seen.insert(id)
                found.append(Entry(id: id, name: name.prefix(1).uppercased() + name.dropFirst()))
                if found.count >= limit { return found }
            }
        }
        return found
    }

    /// Every exercise of the catalog once, under its French alias when it has one, for the
    /// picker's A-to-Z list. Built once: the index never changes while the app runs.
    static let browse: [Entry] = {
        var seen = Set<String>()
        var entries: [Entry] = []
        for source in [index.aliases, index.names] {
            for (name, id) in source.sorted(by: { $0.key < $1.key }) where seen.insert(id).inserted {
                entries.append(Entry(id: id, name: name.prefix(1).uppercased() + name.dropFirst()))
            }
        }
        return entries
    }()

    /// Same normalization as `@sharpit/app/lib/exercises/normalize`.
    nonisolated static func normalize(_ raw: String) -> String {
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
