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
        case "autonomic": "Système nerveux"
        case "sleep": "Sommeil"
        case "subjective": "Ressenti"
        case "loadContext": "Charge"
        default: key
        }
    }

    static func pillarCaption(_ key: String) -> String {
        switch key {
        case "autonomic": "Autonome"
        case "wellness": "Bien-être"
        case "load": "Charge"
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
        case .below: "sous ta norme \(range)"
        case .above: "au-dessus de ta norme \(range)"
        case .within, .unknown: "dans ta norme \(range)"
        }
    }

    static func hrvTone(_ today: V1RecoveryToday) -> Color {
        hrvPosition(today) == .below ? SharpitColor.signalCaution : SharpitColor.foreground
    }

    /// "Récupération complète d'ici 1 jour", "… 3 jours". Nil when nothing is estimated.
    static func recoveryHorizon(_ days: Double?) -> String? {
        guard let days else { return nil }
        let rounded = Int(days.rounded(.up))
        if rounded <= 0 { return "Récupération complète" }
        return "Récupération complète d'ici \(rounded) jour\(rounded > 1 ? "s" : "")"
    }
}
