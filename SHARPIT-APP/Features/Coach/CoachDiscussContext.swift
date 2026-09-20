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
    /// Typed as JSON rather than strings because the server compares the horizon against
    /// numbers: a `"7"` fails that check and the message is read as an ordinary question.
    var metadata: [String: JSONValue] {
        var fields: [String: JSONValue] = ["discussKind": .string(target.kind)]
        switch target {
        case .today:
            break
        case .plannedSession(let sessionId):
            fields["sessionId"] = .string(sessionId)
        case .activity(let activityId):
            fields["activityId"] = .string(activityId)
        case .planning(let horizonDays):
            fields["horizonDays"] = .number(Double(horizonDays))
        }
        return fields
    }
}

nonisolated extension CoachDiscussContext {
    /// Rebuilds the context of a stored turn from its metadata.
    ///
    /// The server keeps the kind and the target id, not the name the athlete saw, so the label
    /// degrades to the kind alone. Nil for a kind the app cannot reach, which reads as an
    /// ordinary turn.
    init?(storedMetadata metadata: JSONValue) {
        guard let kind = metadata["discussKind"]?.string else { return nil }

        let target: CoachDiscussTarget
        switch kind {
        case "today":
            target = .today
        case "planned-session":
            guard let id = metadata["sessionId"]?.string else { return nil }
            target = .plannedSession(sessionId: id)
        case "activity":
            guard let id = metadata["activityId"]?.string else { return nil }
            target = .activity(activityId: id)
        case "planning":
            // A number when the web wrote it, a string when this app did.
            let days: Int? = switch metadata["horizonDays"] {
            case .number(let value)?: Int(value)
            case .string(let value)?: Int(value)
            default: nil
            }
            guard let days else { return nil }
            target = .planning(horizonDays: days)
        default:
            return nil
        }
        self = CoachDiscuss.describe(target)
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
