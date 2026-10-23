import Foundation

/// What the composer's « + » offers: a starting point for a question the coach answers well,
/// as a tag on the conversation plus the first words in the field. The athlete finishes the
/// sentence and sends it; nothing goes out on the tap.
enum CoachQuickAction: CaseIterable, Identifiable {
    case adjustWeek, adjustSession, tiredOrHurt, timeOff, nutrition

    var id: Self { self }

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
        case .adjustSession: "slider.horizontal.3"
        case .tiredOrHurt: "bandage"
        case .timeOff: "calendar.badge.minus"
        case .nutrition: "fork.knife"
        }
    }

    /// The first words of the question, left open for the athlete to finish.
    var draft: String {
        switch self {
        case .adjustWeek: String(localized: "Adapte ma semaine : ")
        case .adjustSession: String(localized: "Ajuste ma séance d'aujourd'hui : ")
        case .tiredOrHurt: String(localized: "Je suis fatigué ou blessé : ")
        case .timeOff: String(localized: "Je ne peux pas m'entraîner ")
        case .nutrition: String(localized: "À propos de mon alimentation : ")
        }
    }

    /// What the conversation is tagged with, so the coach reads the right part of the athlete's data.
    func context(trainingDayId: String) -> CoachDiscussContext {
        switch self {
        case .adjustWeek, .tiredOrHurt, .timeOff: CoachDiscuss.describe(.planning(horizonDays: 7))
        case .adjustSession: CoachDiscuss.describe(.today)
        case .nutrition: CoachDiscuss.describe(.nutrition(trainingDayId: trainingDayId))
        }
    }
}
