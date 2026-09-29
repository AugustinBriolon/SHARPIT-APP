import Foundation
import SwiftUI

/// How Santé says what the web measured: each marker's name, its value in the athlete's words,
/// and the sentence its month makes. Formatting only — every band, trend and alert is the web's
/// (SHARPIT ADR-053).
enum SanteReadout {
    static func title(_ key: V1HealthMarker.Key) -> String {
        switch key {
        case .restingHr: "FC de repos"
        case .hrv: "VFC"
        case .sleep: "Sommeil"
        case .vo2max: "VO₂max"
        case .weight: "Poids"
        case .bodyFatPct: "Masse grasse"
        case .visceralFat: "Graisse viscérale"
        case .musclePct: "Muscle"
        case .steps: "Pas"
        case .respiration: "Respiration"
        }
    }

    static func symbol(_ key: V1HealthMarker.Key) -> String {
        switch key {
        case .restingHr: "heart"
        case .hrv: "waveform.path.ecg"
        case .sleep: "moon.zzz"
        case .vo2max: "lungs"
        case .weight: "scalemass"
        case .bodyFatPct: "drop"
        case .visceralFat: "circle.dotted"
        case .musclePct: "figure.strengthtraining.traditional"
        case .steps: "figure.walk"
        case .respiration: "wind"
        }
    }

    /// What the marker is and why it matters, for its sheet.
    static func explanation(_ key: V1HealthMarker.Key) -> String {
        switch key {
        case .restingHr:
            "Ton cœur au repos. Plus il est bas, plus il travaille peu pour les mêmes besoins : il baisse avec l'endurance et monte avec la fatigue, le stress ou une maladie qui couve."
        case .hrv:
            "La variabilité entre deux battements. Elle reflète la récupération de ton système nerveux : haute quand tu es reposé, basse quand le corps est sollicité. Elle se lit contre ta propre plage, pas contre celle des autres."
        case .sleep:
            "La durée moyenne de tes nuits. C'est pendant le sommeil que le corps répare ce que l'entraînement abîme."
        case .vo2max:
            "Ta capacité cardio-respiratoire maximale. C'est l'un des marqueurs les plus liés à la longévité, et il se travaille."
        case .weight:
            "Ton poids, à lire sur la durée : d'un jour à l'autre, l'eau et les repas le font varier sans rien dire de ta forme."
        case .bodyFatPct:
            "La part de graisse dans ton poids. Une valeur trop basse est aussi un signal : les hormones et l'immunité en ont besoin."
        case .visceralFat:
            "La graisse autour des organes, la plus liée aux risques cardio-métaboliques. Mesurée par ta balance."
        case .musclePct:
            "La part de muscle dans ton poids, selon ta balance. Elle protège les articulations et le métabolisme."
        case .steps:
            "Ton activité en dehors de l'entraînement. Bouger dans la journée compte, même les jours sans séance."
        case .respiration:
            "Ton rythme respiratoire pendant le sommeil. Une hausse inhabituelle accompagne souvent une infection qui commence."
        }
    }

    /// The value and its unit, as the tile writes them.
    static func value(_ marker: V1HealthMarker) -> (text: String, unit: String?) {
        switch marker.key {
        case .sleep: (hoursMinutes(marker.value), nil)
        case .steps: (number(marker.value, digits: 0), "pas")
        case .restingHr: (number(marker.value, digits: 0), "bpm")
        case .hrv: (number(marker.value, digits: 0), "ms")
        case .vo2max: (number(marker.value, digits: 0), "mL/kg/min")
        case .weight: (number(marker.value, digits: 1), "kg")
        case .bodyFatPct, .musclePct: (number(marker.value, digits: 1), "%")
        case .visceralFat: (number(marker.value, digits: 0), "indice")
        case .respiration: (number(marker.value, digits: 1), "/min")
        }
    }

    /// « moyenne 7 jours » or the day of the reading.
    static func basis(_ marker: V1HealthMarker) -> String {
        switch marker.basis {
        case .average7: return "moyenne 7 jours"
        case .latest:
            guard let date = marker.measuredAt else { return "dernière mesure" }
            return date.sharpitFormatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// The month in one line: stable, or the change with its sign and unit.
    static func trend(_ marker: V1HealthMarker) -> String? {
        guard let trend = marker.trend else { return nil }
        // The web already weighed the change against the marker's everyday noise.
        if trend.stable { return "Stable sur le mois" }
        return "\(signedDelta(trend.delta, for: marker.key)) sur le mois"
    }

    /// « Tes 7 derniers jours : 47 bpm · le mois d'avant : 50 bpm ».
    static func comparison(_ marker: V1HealthMarker, trend: V1HealthTrend) -> String {
        let recent = value(V1HealthMarker(key: marker.key, value: trend.recent))
        let before = value(V1HealthMarker(key: marker.key, value: trend.baseline))
        let unit = recent.unit.map { " \($0)" } ?? ""
        let span = marker.basis == .average7 ? "Tes 7 derniers jours" : "Ta dernière période"
        return "\(span) : \(recent.text)\(unit) · le mois d'avant : \(before.text)\(unit)"
    }

    /// « FC de repos −3 bpm » — a highlight of the synthesis.
    static func highlight(_ highlight: V1HealthHighlight) -> String {
        "\(title(highlight.key)) \(signedDelta(highlight.delta, for: highlight.key))"
    }

    /// « 7 repères sur 8 dans leur norme »; nil when nothing could be normed.
    static func synthesis(_ synthesis: V1HealthSynthesis) -> String? {
        guard synthesis.normed > 0 else { return nil }
        if synthesis.inNorm == synthesis.normed {
            return synthesis.normed == 1 ? "Ton repère est dans sa norme" : "Tes \(synthesis.normed) repères sont dans leur norme"
        }
        return "\(synthesis.inNorm) repères sur \(synthesis.normed) dans leur norme"
    }

    /// The Corps metric whose longer history the web keeps, for the sheet's ranges.
    static func corpsKey(_ key: V1HealthMarker.Key) -> CorpsMetricKey? {
        switch key {
        case .restingHr: .restingHr
        case .hrv: .hrv
        case .vo2max: .vo2maxRun
        case .weight: .weight
        case .bodyFatPct: .bodyFatPct
        case .visceralFat: .visceralFat
        case .musclePct: .musclePct
        case .sleep, .steps, .respiration: nil
        }
    }

    // MARK: - Numbers

    static func signedDelta(_ delta: Double, for key: V1HealthMarker.Key) -> String {
        let sign = delta > 0 ? "+" : delta < 0 ? "−" : ""
        let magnitude = abs(delta)
        switch key {
        case .sleep: return "\(sign)\(number(magnitude, digits: 0)) min"
        case .steps: return "\(sign)\(number(magnitude, digits: 0)) pas"
        case .restingHr: return "\(sign)\(number(magnitude, digits: 0)) bpm"
        case .hrv: return "\(sign)\(number(magnitude, digits: 0)) ms"
        case .vo2max: return "\(sign)\(number(magnitude, digits: 1))"
        case .weight: return "\(sign)\(number(magnitude, digits: 1)) kg"
        case .bodyFatPct, .musclePct: return "\(sign)\(number(magnitude, digits: 1)) pt"
        case .visceralFat: return "\(sign)\(number(magnitude, digits: 0))"
        case .respiration: return "\(sign)\(number(magnitude, digits: 1))/min"
        }
    }

    static func hoursMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return "\(total / 60) h \(String(format: "%02d", total % 60))"
    }

    static func number(_ value: Double, digits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...digits))
                .locale(Locale(identifier: "fr_FR"))
        )
    }
}

extension V1HealthTone {
    /// Colour only for a semantic state (`docs/adr/0004`).
    var color: Color {
        switch self {
        case .good: SharpitColor.signalRecovery
        case .neutral: SharpitColor.mutedForeground
        case .watch: SharpitColor.signalCaution
        }
    }
}
