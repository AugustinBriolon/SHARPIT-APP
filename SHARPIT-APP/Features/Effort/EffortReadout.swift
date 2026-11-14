import SwiftUI

/// Words and tones for the Effort screen, kept out of the view so they can be tested. The
/// figures are the server's; this only says them.
enum EffortReadout {
    /// The strain scale's top — the web's ring runs 0–21.
    static let strainScale = 21

    /// « 12,4 » — a strain reads to the tenth. « — » when the day has none.
    static func strain(_ score: Double?) -> String {
        guard let score else { return "—" }
        return score.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.locale))
    }

    /// The limiting factor as words. The server sends them resolved; a server older than
    /// SHARPIT-WEBAPP 39f4b0b3 sent the i18n key instead, so the known keys are worded here too.
    /// shortcut: copies `french.ts`' six lines, drop once every deployed server sends words.
    static func limitingFactor(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard raw.hasPrefix("fatigue.primaryLimitingFactor.") else { return raw }
        switch raw.dropFirst("fatigue.primaryLimitingFactor.".count) {
        case "load": return String(localized: "La charge d’entraînement est le principal levier aujourd’hui.")
        case "neuromuscular": return String(localized: "La récupération neuromusculaire est le principal levier.")
        case "metabolic": return String(localized: "La fatigue métabolique est le principal levier.")
        case "cumulative": return String(localized: "L’historique de charge sur plusieurs semaines pèse le plus.")
        case "psychological": return String(localized: "Le stress psychologique est le principal levier.")
        case "multiple": return String(localized: "Plusieurs dimensions contribuent à la fatigue.")
        default: return nil
        }
    }

    /// The web's `CAPACITY_LABEL`.
    static func capacity(_ key: String) -> String? {
        switch key {
        case "FULL": String(localized: "Capacité totale")
        case "REDUCED": String(localized: "Capacité réduite")
        case "LIGHT_ONLY": String(localized: "Activité légère uniquement")
        case "REST_ONLY": String(localized: "Repos uniquement")
        default: nil
        }
    }

    /// The hero's one line under the strain, the web's `effortActionLine`: when the athlete is
    /// fresh again, else how many days have stacked up, else the kind of fatigue.
    static func actionLine(_ effort: V1EffortResponse) -> String? {
        if let days = effort.estimatedDaysToFresh, days > 0 {
            let rounded = Int(days.rounded(.up))
            return String(localized: "Frais dans \(rounded) jour\(rounded > 1 ? "s" : "")")
        }
        let consecutive = Int(effort.consecutiveDays.rounded())
        if consecutive > 1 {
            return String(localized: "\(consecutive) j d'accumulation")
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
    static func dailyCaption(isExpert: Bool) -> String { isExpert ? String(localized: "TSS du jour") : String(localized: "Charge du jour") }
    static func rampCaption(isExpert: Bool) -> String { isExpert ? "ACWR" : String(localized: "Montée") }
    static func formCaption(isExpert: Bool) -> String { isExpert ? "TSB" : String(localized: "Forme") }

    static func load(_ value: Double) -> String { "\(Int(value.rounded()))" }

    /// The web's `ACWR_SWEET_SPOT`.
    static let rampSweetSpot: ClosedRange<Double> = 0.9...1.3

    /// « 1,21 »; « — » when no ratio can be read yet (the web shows nothing at 0).
    static func ramp(_ acwr: Double) -> String {
        guard acwr > 0 else { return "—" }
        return acwr.formatted(.number.precision(.fractionLength(2)).locale(AppLanguage.locale))
    }

    /// The web's `acwrZoneLabel`.
    static func rampZone(_ acwr: Double) -> String? {
        guard acwr > 0 else { return nil }
        if acwr < 0.9 { return "Sous-charge" }
        if acwr <= 1.3 { return String(localized: "Zone optimale") }
        if acwr <= 1.5 { return String(localized: "Alerte") }
        return String(localized: "Danger")
    }

    /// The ramp's zone as a status: the sweet spot reads good, either side is to watch.
    static func rampStatus(_ acwr: Double) -> CliniqueStatus {
        rampSweetSpot.contains(acwr) ? .good : .watch
    }

    /// Where the day sits against the advised zone, in words; nil without a zone.
    static func zoneWord(_ status: String?) -> String? {
        switch status {
        case "below": String(localized: "Sous ta zone")
        case "within": String(localized: "Dans ta zone")
        case "above": String(localized: "Au-dessus")
        default: nil
        }
    }

    static func zoneStatus(_ status: String?) -> CliniqueStatus? {
        switch status {
        case "within": .good
        case "below": .unknown
        case "above": .watch
        default: nil
        }
    }

    /// « L », « M »… for a `yyyy-MM-dd` day; empty when it cannot be read.
    @MainActor static func weekdayInitial(_ day: String, locale: Locale = SharpitLocale.current) -> String {
        guard let date = TrainingDayId.date(day) else { return "" }
        return String(date.formatted(.dateTime.weekday(.narrow).locale(locale)).prefix(1)).uppercased()
    }


    static func form(_ tsb: Double?) -> String {
        tsb.map { TrainingLoadReadout.signed($0) } ?? "—"
    }


    /// « 8 400 » steps, the French way.
    static func steps(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(AppLanguage.locale))
    }
}
