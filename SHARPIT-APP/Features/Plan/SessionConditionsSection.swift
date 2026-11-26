import SwiftUI

/// « Météo prévue »: what the forecast asks of a session still to do, one line per advisory — a
/// glyph, what to do, why. Ink only: the advice is the content, not a status. Absent when the
/// forecast asks nothing (`docs/adr/0041`).
struct SessionConditionsSection: View {
    let advisories: [V1SessionAdvisory]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("Météo prévue")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(advisories.enumerated()), id: \.element) { index, advisory in
                    if index > 0 { CliniqueDivider() }
                    line(advisory)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ advisory: V1SessionAdvisory) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Image(systemName: advisory.symbolName)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(advisory.headline)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(advisory.rationale)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, SharpitSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

/// How an advisory words itself — the web's copy (`presentation/planned-session`), in « tu ».
extension V1SessionAdvisory {
    var headline: String {
        switch self {
        case .reduceIntensity: String(localized: "Réduire l’intensité prévue")
        case .shiftEarlier: String(localized: "Envisager un créneau plus tôt")
        case .hydration: String(localized: "Hydratation renforcée")
        case .indoorAlternative: String(localized: "Alternative en intérieur possible")
        case .recoveryDemand: String(localized: "Récupération plus exigeante")
        case .rainRisk: String(localized: "Pluie probable sur le créneau")
        case .coldRisk: String(localized: "Froid marqué attendu")
        }
    }

    var rationale: String {
        switch self {
        case .reduceIntensity:
            String(localized: "Forte chaleur prévue pour une séance intense : vise la qualité plutôt que la charge.")
        case .shiftEarlier:
            String(localized: "Les températures montent dans la journée : un départ matinal limite le stress thermique.")
        case .hydration:
            String(localized: "Chaleur ou humidité prévues : prévois plus à boire avant et pendant la séance.")
        case .indoorAlternative:
            String(localized: "Les conditions pèseront nettement sur ta performance : le home trainer ou le tapis restent une option.")
        case .recoveryDemand:
            String(localized: "La séance demandera plus de récupération que prévu : garde de la marge les jours suivants.")
        case .rainRisk:
            String(localized: "De la pluie est attendue : sol glissant, prudence dans les virages et les descentes.")
        case .coldRisk:
            String(localized: "Températures basses attendues : échauffe-toi plus longtemps, couvre-toi et méfie-toi du verglas.")
        }
    }

    var symbolName: String {
        switch self {
        case .reduceIntensity: "gauge.with.dots.needle.33percent"
        case .shiftEarlier: "sunrise"
        case .hydration: "drop"
        case .indoorAlternative: "house"
        case .recoveryDemand: "bed.double"
        case .rainRisk: "cloud.rain"
        case .coldRisk: "thermometer.snowflake"
        }
    }
}
