import ActivityKit
import Foundation

/// Live Activity for a coach turn the athlete left mid-reply.
///
/// `nonisolated`: ActivityKit updates off the main actor; default main-actor isolation
/// would trap the conformance in `@concurrent` contexts.
nonisolated struct CoachReplyAttributes: ActivityAttributes {
    var conversationId: String

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var phase: Phase
        var preview: String

        init(phase: Phase, preview: String = "") {
            self.phase = phase
            self.preview = preview
        }
    }

    nonisolated enum Phase: String, Codable, Hashable, Sendable {
        case replying, ready, failed
    }

    init(conversationId: String) {
        self.conversationId = conversationId
    }
}

/// One short lock-screen line from the coach's answer.
nonisolated enum CoachReplyPreview {
    static let maxLength = 80

    static func line(from text: String, max: Int = maxLength) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > max else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: max - 1)
        return String(collapsed[..<end]) + "…"
    }
}

/// French copy on the Live Activity surfaces.
nonisolated enum CoachReplyLiveActivityCopy {
    static let title = String(localized: "Coach")

    /// The state in a few words; the reply's first line, when there is one, sits under it.
    static func headline(phase: CoachReplyAttributes.Phase) -> String {
        switch phase {
        case .replying: String(localized: "Te répond…")
        case .ready: String(localized: "Réponse prête")
        case .failed: String(localized: "Réponse interrompue")
        }
    }

    /// What goes under the headline: the reply's start once ready, the way back once failed.
    static func detail(phase: CoachReplyAttributes.Phase, preview: String) -> String? {
        switch phase {
        case .replying: nil
        case .ready: preview.isEmpty ? nil : preview
        case .failed: String(localized: "Rouvre SharpIt pour la reprendre.")
        }
    }
}

/// Whether a Live Activity may start for this turn — pure, so the rules are tested.
nonisolated enum CoachReplyLiveActivityGate {
    static func shouldStart(
        isReplying: Bool,
        preferenceEnabled: Bool,
        activitiesEnabled: Bool
    ) -> Bool {
        isReplying && preferenceEnabled && activitiesEnabled
    }
}
