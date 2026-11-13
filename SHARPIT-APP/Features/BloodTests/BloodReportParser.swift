import Foundation

/// One piece of text of a report with where it sits on its page. Any unit works for the geometry
/// (PDF points, Vision's 0...1) as long as y grows upward and one page keeps one unit.
nonisolated struct ReportTextLine: Equatable, Sendable {
    let text: String
    let page: Int
    let midY: Double
    let minX: Double
    let height: Double
    /// 1 for a PDF text layer; the recogniser's own confidence for a photo.
    let confidence: Double
}

nonisolated struct ParsedBloodResult: Equatable, Sendable {
    let markerKey: String
    var value: Double
    let unit: String
    var refLow: Double?
    var refHigh: Double?
    let confidence: Double
}

nonisolated struct ParsedBloodReport: Equatable, Sendable {
    var sampledAt: Date?
    var results: [ParsedBloodResult]
}

nonisolated enum BloodReportText {
    /// Folds what differs between labs and recognisers but not in meaning: case, accents, the
    /// typographic minus labs print in ranges, the two micro signs, the accreditation marks.
    static func folded(_ text: String) -> String {
        var folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        for (from, to) in [("−", "-"), ("–", "-"), ("—", "-"), ("µ", "u"), ("μ", "u"), ("²", "2"),
                           ("*", ""), ("#", "")] {
            folded = folded.replacingOccurrences(of: from, with: to)
        }
        return folded.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    static func number(_ text: Substring) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

/// Reads results out of a lab report from the position of its text, never from its reading order:
/// a PDF text layer lists a value before or after its label depending on the layout, while the
/// value always sits on the label's own line. Identity lines match no marker and are dropped.
nonisolated enum BloodReportParser {
    static func parse(_ lines: [ReportTextLine], calendar: Calendar = .current) -> ParsedBloodReport {
        let rows = rows(from: lines)
        var results: [ParsedBloodResult] = []
        for row in rows {
            guard let result = result(in: row),
                  !results.contains(where: { $0.markerKey == result.markerKey }) else { continue }
            results.append(result)
        }
        let sampledAt = rows.lazy.compactMap { samplingDate(in: $0.text, calendar: calendar) }.first
        return ParsedBloodReport(sampledAt: sampledAt, results: results)
    }

    // MARK: Rows

    private struct Row {
        let text: String
        let confidence: Double
    }

    /// How far apart, in typical line heights of the page, two pieces may sit and still be one
    /// printed line. A method note under a label is a full line lower, so it stays out. The page's
    /// median height is the yardstick because a recogniser's own box heights vary twofold.
    private static let sameRowTolerance = 0.5

    private static func rows(from lines: [ReportTextLine]) -> [Row] {
        var groups: [[ReportTextLine]] = []
        for (_, pageLines) in Dictionary(grouping: lines, by: \.page).sorted(by: { $0.key < $1.key }) {
            let heights = pageLines.map(\.height).sorted()
            let tolerance = sameRowTolerance * heights[heights.count / 2]
            var row: [ReportTextLine] = []
            for line in pageLines.sorted(by: { $0.midY > $1.midY }) {
                let rowY = row.map(\.midY).reduce(0, +) / Double(max(row.count, 1))
                if !row.isEmpty, abs(rowY - line.midY) > tolerance {
                    groups.append(row)
                    row = []
                }
                row.append(line)
            }
            groups.append(row)
        }
        return groups.map { group in
            let text = group.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
            return Row(text: BloodReportText.folded(text), confidence: group.map(\.confidence).min() ?? 0)
        }
    }

    // MARK: One result

    /// Longest alias first, so « cholesterol total » is not read as the bare « cholesterol ».
    private static let aliases: [(alias: String, marker: BloodMarker)] = BloodMarkerCatalog.all
        .flatMap { marker in marker.aliases.map { (alias: $0, marker: marker) } }
        .sorted { $0.alias.count > $1.alias.count }

    private static func result(in row: Row) -> ParsedBloodResult? {
        guard let (alias, marker) = aliases.first(where: { row.text.starts(with: $0.alias, wholeWord: true) })
        else { return nil }
        let rest = row.text.dropFirst(alias.count)
        let unit = NSRegularExpression.escapedPattern(for: BloodReportText.folded(marker.unit))
        // The marker's own unit picks the value: « 46,6 % 1,70 G/L » yields 1,70 for a G/L marker.
        guard let value = try? Regex("([0-9]+(?:[.,][0-9]+)?) ?\(unit)(?![a-z0-9/])", as: (Substring, Substring).self),
              let match = rest.firstMatch(of: value),
              let number = BloodReportText.number(match.1) else { return nil }
        let bounds = referenceBounds(after: rest[match.range.upperBound...])
        return ParsedBloodResult(markerKey: marker.key, value: number, unit: marker.unit,
                                 refLow: bounds.low, refHigh: bounds.high, confidence: row.confidence)
    }

    /// « (4,39-5,68) », « (< 1,50) » or « (> 0,40) » right after the unit; anything else is no bound.
    private static func referenceBounds(after text: Substring) -> (low: Double?, high: Double?) {
        let range = #/\s*\(\s*(?<low>[0-9]+(?:[.,][0-9]+)?)\s*-\s*(?<high>[0-9]+(?:[.,][0-9]+)?)\s*\)/#
        let side = #/\s*\(\s*(?<side><|>)\s*(?<bound>[0-9]+(?:[.,][0-9]+)?)\s*\)/#
        if let range = text.prefixMatch(of: range) {
            return (BloodReportText.number(range.low), BloodReportText.number(range.high))
        }
        if let oneSided = text.prefixMatch(of: side) {
            let bound = BloodReportText.number(oneSided.bound)
            return oneSided.side == "<" ? (nil, bound) : (bound, nil)
        }
        return (nil, nil)
    }

    // MARK: Sampling date

    private static func samplingDate(in row: String, calendar: Calendar) -> Date? {
        let pattern = #/preleve le\s*:?\s*(?<day>[0-9]{2})[-/](?<month>[0-9]{2})[-/](?<year>[0-9]{4})(?:\s+(?<hour>[0-9]{2}):(?<minute>[0-9]{2}))?/#
        guard let match = row.firstMatch(of: pattern) else { return nil }
        let components = DateComponents(
            year: Int(match.year), month: Int(match.month), day: Int(match.day),
            hour: match.hour.flatMap { Int($0) } ?? 8, minute: match.minute.flatMap { Int($0) } ?? 0
        )
        return calendar.date(from: components)
    }
}

nonisolated private extension String {
    /// True when the string starts with `prefix` and the prefix does not end inside a word.
    func starts(with prefix: String, wholeWord: Bool) -> Bool {
        guard hasPrefix(prefix) else { return false }
        guard wholeWord, let next = dropFirst(prefix.count).first else { return true }
        return !(next.isLetter || next.isNumber)
    }
}
