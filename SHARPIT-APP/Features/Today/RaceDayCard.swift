import SwiftUI

/// The race at the head of Résumé: on the day, what is raced and the aim; once run, a quiet
/// summary — the time against the aim, the legs — that invites a look back at the session. On a panel, not ink: the verdict plate under it is
/// the screen's one inverted surface, and two in a row read as two heroes.
struct RaceDayCard: View {
    let race: RaceMomentModel
    /// The card opens the race's session; without one there is no chevron.
    var opensSession = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                CliniqueStatusPill(race.eyebrow, status: .pro)
                Spacer(minLength: 0)
                if opensSession {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SharpitColor.slate)
                        .accessibilityHidden(true)
                }
            }
            Text(race.title)
                .font(SharpitTypography.system(size: 22, weight: .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let result = race.result {
                Text(result.summaryLine)
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityLabel(result.spokenSummary)
                if !result.segments.isEmpty {
                    RaceLegsBar(segments: result.segments, compact: true)
                }
            } else {
                let lines = [race.formatLine, race.targetLine].compactMap { $0 }
                if !lines.isEmpty {
                    Text(lines.joined(separator: " · "))
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            Text(race.coachLine)
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .foregroundStyle(race.result == nil ? SharpitColor.foreground : SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cliniqueCard(border: SharpitColor.pillarCoach.opacity(0.35))
        .accessibilityElement(children: .combine)
        .accessibilityHint(opensSession ? String(localized: "Revoir la course") : "")
    }
}

#Preview("Jour J") {
    RaceDayCard(race: RaceMomentModel(
        goalId: "g", eyebrow: String(localized: "Jour J"), title: String(localized: "Triathlon de Paris"), formatLine: String(localized: "Triathlon M"),
        targetLine: String(localized: "Objectif · Sub 2h30"), coachLine: String(localized: "Le travail est fait. Pars à ton allure, le reste suit.")
    ))
    .padding()
}

#Preview("Course terminée") {
    let legs = [
        V1MultisportLeg(kind: "swim", label: String(localized: "Natation"), durationSec: 1_710, movingDurationSec: nil, distanceM: 1_500, avgHr: nil, avgSpeedMs: nil, elevationM: nil, calories: nil, transitionIndex: nil),
        V1MultisportLeg(kind: "transition", label: "T1", durationSec: 150, movingDurationSec: nil, distanceM: nil, avgHr: nil, avgSpeedMs: nil, elevationM: nil, calories: nil, transitionIndex: 1),
        V1MultisportLeg(kind: "bike", label: String(localized: "Vélo"), durationSec: 4_380, movingDurationSec: nil, distanceM: 40_000, avgHr: nil, avgSpeedMs: nil, elevationM: nil, calories: nil, transitionIndex: nil),
        V1MultisportLeg(kind: "transition", label: "T2", durationSec: 90, movingDurationSec: nil, distanceM: nil, avgHr: nil, avgSpeedMs: nil, elevationM: nil, calories: nil, transitionIndex: 2),
        V1MultisportLeg(kind: "run", label: String(localized: "Course"), durationSec: 2_640, movingDurationSec: nil, distanceM: 10_000, avgHr: nil, avgSpeedMs: nil, elevationM: nil, calories: nil, transitionIndex: nil),
    ]
    RaceDayCard(
        race: RaceMomentModel(
            goalId: "g", eyebrow: String(localized: "Hier · Course terminée"), title: String(localized: "Triathlon de Paris"), formatLine: String(localized: "Triathlon M"),
            targetLine: nil, coachLine: String(localized: "Reviens sur ta course : ce qui a marché, où tu peux progresser."),
            result: RaceResultModel.make(durationSec: nil, legs: legs, targetPerformance: String(localized: "Sub 2h30")),
            activityId: "a"
        ),
        opensSession: true
    )
    .padding()
}
