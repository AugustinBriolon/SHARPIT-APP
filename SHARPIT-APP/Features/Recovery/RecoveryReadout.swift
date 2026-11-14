import SwiftUI

/// Labels and tones for the recovery screen, kept out of the view so they can be tested.
enum RecoveryReadout {
    /// Read as text and marks: the intensity ramp's light grey and lime are fills, unreadable as
    /// type on a white card (ADR-085), so only caution and risk keep a hue.
    static func tone(for signal: V1SignalTone) -> Color {
        switch signal {
        case .strong, .good, .elevated: SharpitColor.primary
        case .moderate: SharpitColor.signalTempo
        case .caution: SharpitColor.signalCaution
        case .risk: SharpitColor.signalRisk
        case .neutral: SharpitColor.signalNeutral
        }
    }

    /// The web's `PRIMARY_LIMITER_LABEL` wording, shortened to fit a bar's caption.
    static func dimensionLabel(_ key: String) -> String {
        switch key {
        case "autonomic": String(localized: "Système nerveux")
        case "sleep": String(localized: "Sommeil")
        case "subjective": String(localized: "Ressenti")
        case "loadContext": String(localized: "Charge")
        default: key
        }
    }

    static func pillarCaption(_ key: String) -> String {
        switch key {
        case "autonomic": String(localized: "Autonome")
        case "wellness": "Bien-être"
        case "load": String(localized: "Charge")
        default: key
        }
    }

    /// A dimension score's tone, with the web's `mapScoreToColorClass` bands.
    static func scoreTone(_ score: Double?) -> Color {
        guard let score else { return SharpitColor.signalNeutral }
        if score >= 60 { return SharpitColor.primary }
        if score >= 40 { return SharpitColor.signalCaution }
        return SharpitColor.signalRisk
    }

    /// Where this morning's HRV sits against the athlete's own normal range.
    enum HRVPosition: Equatable {
        case below, within, above, unknown
    }

    static func hrvPosition(_ today: V1RecoveryToday) -> HRVPosition {
        guard let hrv = today.hrv, let low = today.hrvBaselineLow, let high = today.hrvBaselineHigh else {
            return .unknown
        }
        if hrv < low { return .below }
        if hrv > high { return .above }
        return .within
    }

    static func hrvNote(_ today: V1RecoveryToday) -> String? {
        guard let low = today.hrvBaselineLow, let high = today.hrvBaselineHigh else { return nil }
        let range = "\(Int(low.rounded()))–\(Int(high.rounded()))"
        return switch hrvPosition(today) {
        case .below: String(localized: "sous ta norme \(range)")
        case .above: String(localized: "au-dessus de ta norme \(range)")
        case .within, .unknown: String(localized: "dans ta norme \(range)")
        }
    }

    /// "Récupération complète d'ici 1 jour", "… 3 jours". Nil when nothing is estimated.
    static func recoveryHorizon(_ days: Double?) -> String? {
        guard let days else { return nil }
        let rounded = Int(days.rounded(.up))
        if rounded <= 0 { return String(localized: "Récupération complète") }
        return String(localized: "Récupération complète d'ici \(rounded) jour\(rounded > 1 ? "s" : "")")
    }

    // MARK: - The sheet

    /// The signal as a status: its ring, its dots, its pills.
    static func status(for signal: V1SignalTone) -> CliniqueStatus {
        switch signal {
        case .strong, .good, .elevated, .moderate: .good
        case .caution: .watch
        case .risk: .alert
        case .neutral: .unknown
        }
    }

    /// A dimension's status, with the web's `mapScoreToColorClass` bands.
    static func status(score: Double?) -> CliniqueStatus {
        guard let score else { return .unknown }
        if score >= 60 { return .good }
        return score >= 40 ? .watch : .alert
    }

    /// The sentence under the state: why, in the server's first words; else the advised intensity.
    static func summary(_ recovery: V1RecoveryResponse) -> String {
        recovery.rationale.first ?? String(localized: "Intensité conseillée : \(recovery.intensity)")
    }

    /// « Lecture fiable à 82 % · données complètes ».
    static func reliability(_ recovery: V1RecoveryResponse) -> String {
        let completeness = String(localized: "données \(recovery.completenessLabel.lowercased())")
        guard let pct = recovery.confidencePct else { return completeness.capitalizedFirst }
        return String(localized: "Lecture fiable à \(Int(pct.rounded())) % · \(completeness)")
    }

    /// A line of « Ce qui pèse ».
    struct Weight: Equatable, Identifiable {
        let id: String
        let name: String
        /// « Limite », on the dimension that holds the readiness back.
        var tag: String?
        var detail: String?
        /// Where the reading sits on its track, 0 to 1; nil without a score.
        var position: Double?
        var status: CliniqueStatus
    }

    /// The dimensions of the readiness, the weakest tagged when the server names a limiter.
    static func weights(_ recovery: V1RecoveryResponse) -> [Weight] {
        let weakest = recovery.limiter == nil
            ? nil
            : recovery.dimensions.filter { $0.score != nil }.min { ($0.score ?? 0) < ($1.score ?? 0) }?.key
        return recovery.dimensions.map { dimension in
            Weight(
                id: dimension.key,
                name: dimensionLabel(dimension.key),
                tag: dimension.key == weakest ? String(localized: "Limite") : nil,
                detail: detail(dimension, today: recovery.today),
                position: dimension.score.map { min(max($0 / 100, 0), 1) },
                status: status(score: dimension.score)
            )
        }
    }

    /// What was measured behind a dimension: this morning's HRV against its range for the
    /// nervous system, the score otherwise.
    private static func detail(_ dimension: V1RecoveryDimension, today: V1RecoveryToday) -> String? {
        if dimension.key == "autonomic", let hrv = today.hrv {
            let reading = "\(Int(hrv.rounded())) ms"
            guard let low = today.hrvBaselineLow, let high = today.hrvBaselineHigh else { return reading }
            return String(localized: "\(reading) · ta plage \(Int(low.rounded())) – \(Int(high.rounded()))")
        }
        return dimension.score.map { String(localized: "\(Int($0.rounded())) sur 100") }
    }
}
