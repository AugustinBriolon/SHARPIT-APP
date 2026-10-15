import ActivityKit
import Foundation

/// Live Activity for a guided strength session (active set + timed rest).
///
/// `nonisolated`: ActivityKit updates off the main actor; default main-actor isolation
/// would trap the conformance in `@concurrent` contexts.
nonisolated struct GuidedStrengthRestAttributes: ActivityAttributes {
    var sessionTitle: String
    var startedAt: Date

    nonisolated enum Kind: String, Codable, Hashable, Sendable {
        case active
        case resting
    }

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var kind: Kind
        /// Absolute end of the rest — drives `Text(timerInterval:)` while counting.
        var endsAt: Date?
        /// Frozen seconds while paused (`endsAt` is nil).
        var remainingWhenPaused: Int
        var isPaused: Bool
        var nextExercise: String
        var nextSetLine: String

        init(
            kind: Kind = .active,
            endsAt: Date? = nil,
            remainingWhenPaused: Int = 0,
            isPaused: Bool = false,
            nextExercise: String = "",
            nextSetLine: String = ""
        ) {
            self.kind = kind
            self.endsAt = endsAt
            self.remainingWhenPaused = remainingWhenPaused
            self.isPaused = isPaused
            self.nextExercise = nextExercise
            self.nextSetLine = nextSetLine
        }
    }

    init(sessionTitle: String, startedAt: Date) {
        self.sessionTitle = sessionTitle
        self.startedAt = startedAt
    }
}

/// French copy on the guided-strength Live Activity surfaces.
nonisolated enum GuidedStrengthRestLiveActivityCopy {
    static let restTitle = "Repos"
    static let activeTitle = "Séance"

    static func subtitle(nextExercise: String, nextSetLine: String) -> String {
        let name = nextExercise.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = nextSetLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return line.isEmpty ? "Séance en cours" : line }
        if line.isEmpty { return name }
        return "\(name) · \(line)"
    }

    static func eyebrow(kind: GuidedStrengthRestAttributes.Kind) -> String {
        kind == .resting ? restTitle : activeTitle
    }

    static func pausedLabel(seconds: Int) -> String {
        let total = max(seconds, 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Whether a guided-strength Live Activity may start — pure, so the rules are tested.
nonisolated enum GuidedStrengthRestLiveActivityGate {
    static func shouldStart(
        preferenceEnabled: Bool,
        activitiesEnabled: Bool
    ) -> Bool {
        preferenceEnabled && activitiesEnabled
    }
}
