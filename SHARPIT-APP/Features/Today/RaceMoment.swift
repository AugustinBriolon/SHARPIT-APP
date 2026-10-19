import Foundation

/// Résumé's race card: the race ahead today, or the result once it is run.
struct RaceMomentModel: Sendable, Equatable {
    var goalId: String
    /// « Jour J », « Hier · Course terminée »…
    var eyebrow: String
    var title: String
    var formatLine: String?
    /// « Objectif · Sub 2h30 »; dropped once a result says how it went.
    var targetLine: String?
    /// On the day, a word before the start; once run, the invitation to review the race.
    var coachLine: String
    /// Nil until the race's session is in.
    var result: RaceResultModel?
    /// The session the card opens.
    var activityId: String?
}

enum RaceMomentMapper {
    static func map(_ race: V1TodayRace?, trainingDayId: String) -> RaceMomentModel? {
        guard let race, race.phase == "raceDay" || race.phase == "postRace" else { return nil }
        let result = race.activity.flatMap {
            RaceResultModel.make(durationSec: $0.durationSec, legs: $0.legs, targetPerformance: race.targetPerformance)
        }
        let target = race.targetPerformance?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RaceMomentModel(
            goalId: race.goalId,
            eyebrow: eyebrow(race: race, finished: result != nil, trainingDayId: trainingDayId),
            title: race.title,
            formatLine: race.raceFormat?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            targetLine: result == nil ? target?.nilIfEmpty.map { String(localized: "Objectif · \($0)") } : nil,
            coachLine: result == nil
                ? String(localized: "Le travail est fait. Pars à ton allure, le reste suit.")
                : String(localized: "Reviens sur ta course : ce qui a marché, où tu peux progresser."),
            result: result,
            activityId: race.activity?.id
        )
    }

    private static func eyebrow(race: V1TodayRace, finished: Bool, trainingDayId: String) -> String {
        guard finished else { return String(localized: "Jour J") }
        switch daysSinceRace(race.targetDate, today: trainingDayId) {
        case 0: return String(localized: "Aujourd’hui · Course terminée")
        case 1: return String(localized: "Hier · Course terminée")
        default: return String(localized: "Course terminée")
        }
    }

    private static func daysSinceRace(_ raceDay: String, today: String) -> Int? {
        guard let race = TrainingDayId.date(String(raceDay.prefix(10))), let now = TrainingDayId.date(today) else { return nil }
        return Calendar.current.dateComponents([.day], from: race, to: now).day
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
