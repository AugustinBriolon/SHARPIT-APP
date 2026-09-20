import Foundation

/// What a contextual coach conversation is about.
///
/// Ported from the web's `coach-discuss-href.ts` / `coach-discuss-context.ts` (ADR-030,
/// ADR-031). The kinds and their labels are the web's, unchanged, because the athlete
/// meets the same chip on both surfaces and the server reads the same discriminant.
///
/// Only the kinds iOS can currently reach are modelled. Adding one is a case plus its
/// label — the same shape the web's registry has.
nonisolated enum CoachDiscussTarget: Equatable, Hashable, Sendable {
    case today
    case plannedSession(sessionId: String)
    case activity(activityId: String)
    case planning(horizonDays: Int)

    /// The discriminant the server reads. Matches the web's `discussKind` strings.
    var kind: String {
        switch self {
        case .today: "today"
        case .plannedSession: "planned-session"
        case .activity: "activity"
        case .planning: "planning"
        }
    }
}

/// The context attached to a conversation, as the athlete reads it.
///
/// The Information Architecture requires a contextual conversation to name what it
/// carries and to let the athlete drop it before sending. This is a tag, not a prefilled
/// prompt: the athlete still writes their own question, and the coach is told what they
/// were looking at.
nonisolated struct CoachDiscussContext: Equatable, Hashable, Sendable, Identifiable {
    let target: CoachDiscussTarget
    /// What is attached, in the athlete's words.
    let label: String

    var id: String { "\(target.kind)-\(label)" }
    var kind: String { target.kind }

    /// Message metadata, mirroring the web's `coachDiscussMetadata`.
    ///
    /// Client-supplied and therefore untrusted: the server shape-checks it, scopes every
    /// lookup to the signed-in athlete, and re-checks entitlements before acting on it.
    var metadata: [String: String] {
        switch target {
        case .today:
            ["discussKind": target.kind]
        case .plannedSession(let sessionId):
            ["discussKind": target.kind, "sessionId": sessionId]
        case .activity(let activityId):
            ["discussKind": target.kind, "activityId": activityId]
        case .planning(let horizonDays):
            ["discussKind": target.kind, "horizonDays": String(horizonDays)]
        }
    }
}

nonisolated enum CoachDiscuss {
    /// Planning window in plain French — shared by the chip and the coach prompt.
    static func planningHorizonLabel(_ horizonDays: Int) -> String {
        switch horizonDays {
        case 1: "demain"
        case 3: "les 3 prochains jours"
        case 7: "les 7 prochains jours"
        case 14: "les 14 prochains jours"
        default: "\(horizonDays) jours"
        }
    }

    /// `name` is the resolved human name of the target — a session title, an activity.
    /// When it is missing the label degrades to the kind alone rather than inventing one.
    static func describe(_ target: CoachDiscussTarget, name: String? = nil) -> CoachDiscussContext {
        let named = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (named?.isEmpty == false) ? named : nil

        let label: String = switch target {
        case .today:
            "Ton état du jour"
        case .plannedSession:
            resolved.map { "Séance prévue · \($0)" } ?? "Une séance prévue"
        case .activity:
            resolved.map { "Séance réalisée · \($0)" } ?? "Une séance réalisée"
        case .planning(let horizonDays):
            "Ta semaine · \(planningHorizonLabel(horizonDays))"
        }

        return CoachDiscussContext(target: target, label: label)
    }
}
