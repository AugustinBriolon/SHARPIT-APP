import Foundation

/// The coach's weekly review split into what the screen shows at a glance: what went well, what
/// to watch, next week — and the two narrative paragraphs, kept for the full reading. Read from
/// the markdown's fixed headings (the web's `weekly-review.ts` prompt); a review written before
/// the split keeps its combined list as `mixed`.
nonisolated struct WeeklyReviewSections: Equatable, Sendable {
    var wins: [String] = []
    var watch: [String] = []
    /// A review from before « Ce qui a bien marché » and « À surveiller » were separate.
    var mixed: [String] = []
    var nextWeek: [String] = []
    var narrative: [(title: String, text: String)] = []

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.wins == rhs.wins && lhs.watch == rhs.watch && lhs.mixed == rhs.mixed
            && lhs.nextWeek == rhs.nextWeek && lhs.narrative.map(\.title) == rhs.narrative.map(\.title)
            && lhs.narrative.map(\.text) == rhs.narrative.map(\.text)
    }

    init(markdown: String) {
        var heading = ""
        for block in SharpitMarkdown.blocks(from: markdown) {
            switch block {
            case .heading(_, let text):
                heading = text
            case .bulleted(let items), .numbered(let items):
                append(items.map(Self.plain), under: heading)
            case .paragraph(let text):
                let title = heading.isEmpty ? "Bilan" : heading
                if let index = narrative.firstIndex(where: { $0.title == title }) {
                    narrative[index].text += "\n\n" + text
                } else {
                    narrative.append((title, text))
                }
            default:
                break
            }
        }
    }

    private mutating func append(_ items: [String], under heading: String) {
        let key = heading.lowercased()
        if key.contains("bien marché") {
            wins += items
        } else if key.contains("surveiller") {
            watch += items
        } else if key.contains("semaine prochaine") {
            nextWeek += items
        } else {
            mixed += items
        }
    }

    /// Markdown emphasis off: the lists are read as plain facts on coloured cards.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
    }
}
