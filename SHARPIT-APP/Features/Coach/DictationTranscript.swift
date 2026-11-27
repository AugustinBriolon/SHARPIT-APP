import Foundation

/// Everything heard in one dictation, kept across the recognizer's restarts.
///
/// On the device the recognizer closes an utterance at each pause and starts the next one from an
/// empty string: its latest partial is the current utterance, never the whole dictation. Writing
/// that partial into the draft as it comes erased what was said before the pause.
struct DictationTranscript: Equatable {
    private var closedUtterances: [String] = []
    private var currentUtterance = ""

    var text: String {
        (closedUtterances + [currentUtterance]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Takes the recognizer's latest partial; `closesUtterance` when it says the utterance is over.
    mutating func hear(_ partial: String, closesUtterance: Bool) {
        let words = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        if Self.startsOver(from: currentUtterance, to: words) { closeCurrentUtterance() }
        currentUtterance = words
        if closesUtterance { closeCurrentUtterance() }
    }

    /// A partial that restarts instead of revising: fewer words, and not the same opening word.
    ///
    /// The recognizer does not always announce the end of an utterance, and a revision keeps the
    /// opening word or the length; only a restart loses both.
    static func startsOver(from previous: String, to next: String) -> Bool {
        let before = previous.split(separator: " ")
        let after = next.split(separator: " ")
        guard let firstBefore = before.first, let firstAfter = after.first else { return false }
        let sameOpening = firstBefore.compare(
            firstAfter, options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
        return after.count < before.count && !sameOpening
    }

    private mutating func closeCurrentUtterance() {
        guard !currentUtterance.isEmpty else { return }
        closedUtterances.append(currentUtterance)
        currentUtterance = ""
    }
}
