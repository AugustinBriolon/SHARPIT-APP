import SwiftUI

/// Words and tones for the Effort screen, kept out of the view so they can be tested. The
/// figures are the server's; this only says them.
enum EffortReadout {
    /// The strain scale's top — the web's ring runs 0–21.
    static let strainScale = 21

    /// « 12,4 » — a strain reads to the tenth. « — » when the day has none.
    static func strain(_ score: Double?) -> String {
        guard let score else { return "—" }
        return score.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
    }

    /// The web's `CAPACITY_LABEL`.
    static func capacity(_ key: String) -> String? {
        switch key {
        case "FULL": "Capacité totale"
        case "REDUCED": "Capacité réduite"
        case "LIGHT_ONLY": "Activité légère uniquement"
        case "REST_ONLY": "Repos uniquement"
        default: nil
        }
    }

    /// The hero's one line under the strain, the web's `effortActionLine`: when the athlete is
    /// fresh again, else how many days have stacked up, else the kind of fatigue.
    static func actionLine(_ effort: V1EffortResponse) -> String? {
        if let days = effort.estimatedDaysToFresh, days > 0 {
            let rounded = Int(days.rounded(.up))
            return "Frais dans \(rounded) jour\(rounded > 1 ? "s" : "")"
        }
        let consecutive = Int(effort.consecutiveDays.rounded())
        if consecutive > 1 {
            return "\(consecutive) j d'accumulation"
        }
        if let label = effort.fatigueTypeLabel, !label.isEmpty {
            return label
        }
        return nil
    }

    /// A fatigue dimension's tone: higher is worse, so the web reads `100 − score` on the
    /// bands every other dimension uses.
    static func dimensionTone(_ dimension: V1EffortDimension) -> Color {
        guard dimension.available, let score = dimension.score else { return SharpitColor.signalNeutral }
        return RecoveryReadout.scoreTone(100 - score)
    }

    // MARK: - Load, named per reading (ADR 0006)

    /// The essential reading keeps the figures and drops the acronyms, as the web's
    /// `formatTrainingLoad` does; the expert one names them.
    static func dailyCaption(isExpert: Bool) -> String { isExpert ? "TSS du jour" : "Charge du jour" }
    static func weeklyCaption(isExpert: Bool) -> String { isExpert ? "TSS 7 j" : "Charge 7 j" }
    static func rampCaption(isExpert: Bool) -> String { isExpert ? "ACWR" : "Montée" }
    static func formCaption(isExpert: Bool) -> String { isExpert ? "TSB" : "Forme" }

    static func load(_ value: Double) -> String { "\(Int(value.rounded()))" }

    /// The web's `ACWR_SWEET_SPOT`.
    static let rampSweetSpot: ClosedRange<Double> = 0.9...1.3

    /// « 1,21 »; « — » when no ratio can be read yet (the web shows nothing at 0).
    static func ramp(_ acwr: Double) -> String {
        guard acwr > 0 else { return "—" }
        return acwr.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_FR")))
    }

    /// The web's `acwrZoneLabel`.
    static func rampZone(_ acwr: Double) -> String? {
        guard acwr > 0 else { return nil }
        if acwr < 0.9 { return "Sous-charge" }
        if acwr <= 1.3 { return "Zone optimale" }
        if acwr <= 1.5 { return "Alerte" }
        return "Danger"
    }

    static func rampTone(_ acwr: Double) -> Color {
        guard acwr > 0 else { return SharpitColor.foreground }
        if rampSweetSpot.contains(acwr) || acwr < 0.9 { return SharpitColor.foreground }
        return acwr <= 1.5 ? SharpitColor.signalCaution : SharpitColor.signalRisk
    }

    static func form(_ tsb: Double?) -> String {
        tsb.map { TrainingLoadReadout.signed($0) } ?? "—"
    }

    static func formTone(_ tsb: Double?) -> Color {
        guard let tsb else { return SharpitColor.foreground }
        return TrainingLoadReadout.isInFormBand(tsb) ? SharpitColor.foreground : SharpitColor.signalCaution
    }

    /// « 8 400 » steps, the French way.
    static func steps(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(Locale(identifier: "fr_FR")))
    }
}
