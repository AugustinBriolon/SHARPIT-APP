import SwiftUI

/// « Ta semaine est prête »: the plan was running out, SharpIt wrote the next week (ADR-095).
/// One tap opens it in Plan's generator, where the athlete keeps what suits them; left alone,
/// the server adds it as written the day before it starts.
struct PlanHorizonCard: View {
    let horizon: V1TodayPlanHorizon
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            SharpitCardHeader(
                title: "Ta semaine est prête",
                symbol: "calendar.badge.plus",
                subtitle: PlanHorizonReadout.subtitle(horizon)
            )
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Ouvre la semaine proposée")
    }
}

enum PlanHorizonReadout {
    /// « 4 séances dès lundi 27 oct. — garde celles qui te vont ».
    static func subtitle(_ horizon: V1TodayPlanHorizon) -> String {
        let count = "\(horizon.sessionCount) séance\(horizon.sessionCount > 1 ? "s" : "")"
        guard let day = TrainingDayId.date(horizon.startDate) else {
            return "\(count) — garde celles qui te vont"
        }
        let label = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(SharpitLocale.french))
        return "\(count) dès \(label) — garde celles qui te vont"
    }
}
