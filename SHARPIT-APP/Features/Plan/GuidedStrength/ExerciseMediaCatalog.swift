import Foundation

/// CDN media for the exercises-dataset catalog (same IDs / aliases as the web app).
enum ExerciseMediaCatalog {
    /// The notice the pictures must carry wherever they are shown (the dataset's `NOTICE.md`).
    static let attribution = "© Gym visual — https://gymvisual.com/"

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
        return closestCatalogId(key)
    }

    /// Words of a French name that say nothing about the movement: « Abdos jackknife (poids du
    /// corps) » is the jackknife sit-up whatever its load.
    private static let fillerWords: Set<String> = [
        "a", "au", "aux", "avec", "d", "de", "des", "du", "en", "et", "l", "la", "le", "les", "sans",
        "sur", "pour", "poids", "corps", "charge", "leger", "legere", "lourd", "lourde",
        "poids du corps", "a vide",
    ]

    private static var closestCache: [String: String?] = [:]

    /// The catalog's exercise a coach's name means when no alias spells it (the coach writes
    /// French, the catalog English): every word read through `ExerciseFrenchGlossary`, the name
    /// holding the most of them kept when it covers at least 60 % of both — the web resolver's
    /// threshold. Most of the coach's names had no picture before (the athlete's remark, 2026-11-28).
    static func closestCatalogId(_ key: String) -> String? {
        if let cached = closestCache[key] { return cached }
        let units = ExerciseFrenchGlossary.alternatives(for: key).filter { !fillerWords.contains($0[0]) }
        var best: (id: String, score: Double, length: Int, rank: Int, name: String)?
        if !units.isEmpty {
            for source in [index.aliases, index.names] {
                for (name, id) in source where index.media[id] != nil {
                    let padded = " \(name) "
                    // Each unit found counts once, and so does each word of the name left over:
                    // « pull up » is one unit for « traction », not two words of which one is missed.
                    // `rank`: how far down each unit's spellings the name was found, so « traction »
                    // takes the glossary's first meaning (« pull up ») over its second.
                    var hits = 0
                    var covered = 0
                    var rank = 0
                    for spellings in units {
                        let found = spellings.enumerated().filter { padded.contains(" \($0.element) ") }
                        guard let first = found.first,
                              let longest = found.map({ $0.element.split(separator: " ").count }).max()
                        else { continue }
                        hits += 1
                        covered += longest
                        rank += first.offset
                    }
                    guard hits > 0 else { continue }
                    let words = name.split(separator: " ").count
                    let length = hits + max(words - covered, 0)
                    let score = Double(hits) / Double(max(units.count, length))
                    let better = best.map {
                        score > $0.score || (score == $0.score && (length, rank, name) < ($0.length, $0.rank, $0.name))
                    } ?? true
                    if better { best = (id, score, length, rank, name) }
                }
            }
        }
        let found = best.flatMap { $0.score >= 0.6 ? $0.id : nil }
        closestCache[key] = .some(found)
        return found
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

    /// The catalog's exercises whose name holds every word typed — as typed or under its English
    /// name (`ExerciseFrenchGlossary`), since the catalog is English and the athlete types French —
    /// aliases first, one line per exercise. Empty for an empty query.
    static func search(_ query: String, limit: Int = 30) -> [Entry] {
        let words = ExerciseFrenchGlossary.alternatives(for: normalize(query))
        guard !words.isEmpty else { return [] }
        var seen = Set<String>()
        var found: [Entry] = []
        for source in [index.aliases, index.names] {
            for (name, id) in source.sorted(by: { $0.key < $1.key }) where !seen.contains(id) {
                guard words.allSatisfy({ spellings in spellings.contains { name.contains($0) } }) else { continue }
                seen.insert(id)
                found.append(Entry(id: id, name: name.prefix(1).uppercased() + name.dropFirst()))
                if found.count >= limit { return found }
            }
        }
        return found
    }

    /// Every exercise of the catalog once, under its first alias when it has one (the French
    /// names are aliases; so are some English ones), for the picker's A-to-Z list. Built once: the index never changes while the app runs.
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
