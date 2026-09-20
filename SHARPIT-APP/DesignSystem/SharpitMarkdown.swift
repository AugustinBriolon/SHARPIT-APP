import Foundation

/// The block structure of a coach answer.
///
/// `AttributedString(markdown:)` handles emphasis, code spans and links, but it collapses
/// block syntax — a heading keeps its hashes, a list loses its bullets, paragraphs run
/// together. The coach writes in paragraphs and lists, so the blocks are parsed here and
/// each one's inline markup is left to Foundation.
///
/// Scoped to what a language model actually emits. Tables, footnotes and nested lists are
/// not parsed: an unrecognised line becomes a paragraph, which reads as itself rather
/// than as a parse error.
nonisolated enum SharpitMarkdownBlock: Equatable, Identifiable, Sendable {
    /// `#`, `##`, `###` — clamped to 3, the deepest a short answer needs.
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulleted([String])
    case numbered([String])
    case quote(String)
    case code(String)
    case rule

    var id: String {
        switch self {
        case .heading(let level, let text): "h\(level)-\(text)"
        case .paragraph(let text): "p-\(text)"
        case .bulleted(let items): "ul-\(items.joined(separator: "|"))"
        case .numbered(let items): "ol-\(items.joined(separator: "|"))"
        case .quote(let text): "q-\(text)"
        case .code(let text): "code-\(text)"
        case .rule: "rule"
        }
    }
}

nonisolated enum SharpitMarkdown {
    /// Splits text into blocks. Never throws and never drops content: anything it does
    /// not recognise survives as a paragraph.
    static func blocks(from markdown: String) -> [SharpitMarkdownBlock] {
        var blocks: [SharpitMarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
        func flushLists() {
            if !bullets.isEmpty {
                blocks.append(.bulleted(bullets))
                bullets = []
            }
            if !numbers.isEmpty {
                blocks.append(.numbered(numbers))
                numbers = []
            }
        }
        func flushAll() {
            flushParagraph()
            flushLists()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(code.joined(separator: "\n")))
                    code = []
                }
                // A fence that never closes still yields its block at the end, so a
                // streaming answer shows its code as it arrives.
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushAll()
                continue
            }
            if isRule(line) {
                flushAll()
                blocks.append(.rule)
                continue
            }
            if let heading = heading(in: line) {
                flushAll()
                blocks.append(heading)
                continue
            }
            if let item = bulletItem(in: line) {
                flushParagraph()
                if !numbers.isEmpty { flushLists() }
                bullets.append(item)
                continue
            }
            if let item = numberedItem(in: line) {
                flushParagraph()
                if !bullets.isEmpty { flushLists() }
                numbers.append(item)
                continue
            }
            if line.hasPrefix(">") {
                flushAll()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }

            flushLists()
            paragraph.append(line)
        }

        if inCode, !code.isEmpty {
            blocks.append(.code(code.joined(separator: "\n")))
        }
        flushAll()
        return blocks
    }

    private static func isRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
    }

    private static func heading(in line: String) -> SharpitMarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= 6 else { return nil }

        let text = String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: min(hashes, 3), text: text)
    }

    private static func bulletItem(in line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedItem(in line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    /// Inline markup — emphasis, code spans, links — resolved for one block.
    ///
    /// A streaming answer is malformed most of the time (`**` with no closer yet), so a
    /// failed parse falls back to the raw text instead of blanking the line.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
