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
    static let title = "Coach"

    static func subtitle(phase: CoachReplyAttributes.Phase, preview: String) -> String {
        switch phase {
        case .replying:
            return "Répond…"
        case .ready:
            return preview.isEmpty ? "Réponse prête" : "Réponse prête · \(preview)"
        case .failed:
            return "Réponse interrompue · rouvre SharpIt"
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
