import Foundation

/// What the composer offers: a starting point for a question the coach answers well, as a tag on
/// the conversation. The field stays the athlete's — empty, its placeholder hinting at the
/// sentence — and nothing goes out on the tap.
enum CoachQuickAction: CaseIterable, Identifiable {
    case adjustWeek, adjustSession, tiredOrHurt, timeOff, nutrition

    var id: Self { self }

    /// The three offered above the box of an empty thread.
    static let suggested: [CoachQuickAction] = [.adjustWeek, .adjustSession, .tiredOrHurt]

    /// What the « + » lists: never a line already on screen above the box.
    static func panel(showingSuggestions: Bool) -> [CoachQuickAction] {
        showingSuggestions ? allCases.filter { !suggested.contains($0) } : allCases
    }

    var label: String {
        switch self {
        case .adjustWeek: String(localized: "Ajuster ma semaine")
        case .adjustSession: String(localized: "Ajuster une séance")
        case .tiredOrHurt: String(localized: "Je suis fatigué ou blessé")
        case .timeOff: String(localized: "Je ne peux pas m'entraîner")
        case .nutrition: String(localized: "Parler de ma nutrition")
        }
    }

    var symbol: String {
        switch self {
        case .adjustWeek: "calendar"
        case .adjustSession: "figure.run"
        case .tiredOrHurt: "bandage"
        case .timeOff: "pause.circle"
        case .nutrition: "fork.knife"
        }
    }

    /// The field's placeholder once the tag is on: what the coach needs to hear, never typed in.
    var prompt: String {
        switch self {
        case .adjustWeek: String(localized: "Qu'est-ce qui change cette semaine ?")
        case .adjustSession: String(localized: "Que veux-tu changer à ta séance ?")
        case .tiredOrHurt: String(localized: "Où, et depuis quand ?")
        case .timeOff: String(localized: "Quels jours, et pourquoi ?")
        case .nutrition: String(localized: "Ta question sur ton alimentation")
        }
    }

    /// What the conversation is tagged with, so the coach reads the right part of the athlete's
    /// data. The tag reads as the action picked, with its glyph.
    func context(trainingDayId: String) -> CoachDiscussContext {
        let target: CoachDiscussTarget = switch self {
        case .adjustWeek, .tiredOrHurt, .timeOff: .planning(horizonDays: 7)
        case .adjustSession: .today
        case .nutrition: .nutrition(trainingDayId: trainingDayId)
        }
        return CoachDiscussContext(target: target, label: label, symbol: symbol, prompt: prompt)
    }
}
