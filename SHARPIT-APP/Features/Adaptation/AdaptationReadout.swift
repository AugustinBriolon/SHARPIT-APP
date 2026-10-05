import SwiftUI

/// Words and tones for the Adaptation screen, kept out of the view so they can be tested.
enum AdaptationReadout {
    /// The dimension the web hides when it has no signal — it needs streams the athlete may
    /// never record — and explains instead.
    static let neuromuscularKey = "neuromuscularEfficiency"

    /// The limiting dimension first, then the others in the server's order; an unavailable
    /// neuromuscular efficiency is left out, as the web leaves it out.
    static func displayedDimensions(_ adaptation: V1AdaptationResponse) -> [V1AdaptationDimension] {
        let shown = adaptation.dimensions.filter { $0.key != neuromuscularKey || $0.available }
        return shown.filter(\.isLimiting) + shown.filter { !$0.isLimiting }
    }

    static func isNeuromuscularMissing(_ adaptation: V1AdaptationResponse) -> Bool {
        adaptation.dimensions.contains { $0.key == neuromuscularKey && !$0.available }
    }

    /// The limiting dimension's score, when it has one.
    static func limitingScore(_ adaptation: V1AdaptationResponse) -> Double? {
        adaptation.dimensions.first { $0.isLimiting && $0.available }?.score
    }

    /// Higher is better, and the web's protective bands only warn: under 60 is a caution.
    static func dimensionTone(_ dimension: V1AdaptationDimension) -> Color {
        guard dimension.available, let score = dimension.score else { return SharpitColor.signalNeutral }
        return score >= 60 ? SharpitColor.primary : SharpitColor.signalCaution
    }

    /// The web's `LIMITER_BAND`: under 40 the brake decides what the athlete can absorb.
    static func limiterTone(_ score: Double?) -> Color {
        guard let score else { return SharpitColor.foreground }
        return score < 40 ? SharpitColor.signalCaution : SharpitColor.foreground
    }

    /// « Neutre » inside ±0,5 %, else « ×0,90 » — the web's marker.
    static func loadMultiplier(_ value: Double) -> String {
        if abs(value - 1) < 0.005 { return "Neutre" }
        return "×" + value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_FR")))
    }

    /// What the multiplier does to the next block, in the web's explanation's words.
    static func loadMultiplierNote(_ value: Double) -> String {
        if value < 0.95 { return "Volume réduit pour laisser l'adaptation rattraper" }
        if value > 1.05 { return "Plus de charge possible" }
        return "Ne change rien"
    }

    /// The trend under the index; nil when none is read.
    static func trend(_ label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "—" ? nil : trimmed
    }

    /// « 42 jours d'historique ».
    static func history(_ days: Double) -> String {
        let count = Int(days.rounded())
        return "\(count) jour\(count > 1 ? "s" : "") d'historique"
    }
}
