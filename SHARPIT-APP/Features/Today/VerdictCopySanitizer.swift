import Foundation
import OSLog

/// Guards server copy against unresolved `{…}` placeholders.
///
/// The server must never leave a brace token in athlete-facing text; if one slips through,
/// the plate shows a neutral fallback and we log the event without any text content or PII.
nonisolated enum VerdictCopySanitizer {
    nonisolated private static let log = Logger(subsystem: "app.sharpit.ios", category: "verdict")

    /// Neutral lines when a displayed string still carries an unreplaced placeholder.
    static let fallbackExplanation = "Le verdict n’est pas disponible pour le moment."
    static let fallbackInstruction = "Suis ton plan avec prudence."

    private static let unresolvedPlaceholder = /\{[^}]+\}/

    static func containsUnresolvedPlaceholder(_ text: String) -> Bool {
        text.contains(unresolvedPlaceholder)
    }

    /// Returns the text when clean, otherwise the fallback and a privacy-safe log line.
    static func display(_ text: String?, fallback: String) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if containsUnresolvedPlaceholder(trimmed) {
            log.warning("verdict.copy.unresolved_placeholder")
            return fallback
        }
        return trimmed
    }
}
