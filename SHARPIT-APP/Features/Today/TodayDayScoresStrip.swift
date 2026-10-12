import SwiftUI

/// ADR-079 fold: Energy Bank · Stress · Target band under overnight gauges.
/// Callers: TodayFoldView in TodayView.swift.
/// API: optional stress / energyBank / targetBand on GET /api/v1/today.
/// Schema: none (computed on read).
/// User: "Implement the plan as specified… Don't stop until you have completed all the to-dos."
struct TodayDayScoresStrip: View {
    let energyBank: V1TodayEnergyBank?
    let stress: V1TodayStress?
    let targetBand: V1TodayTargetBand?

    private var hasContent: Bool {
        energyBank?.value != nil || stress != nil || targetBand != nil
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow("État du jour")
                HStack(spacing: SharpitSpacing.sm) {
                    if let value = energyBank?.value {
                        dayTile(
                            caption: "Réserve",
                            value: "\(Int(value.rounded()))",
                            unit: "/100",
                            note: energyBank?.typicalBaseline.map { "typ. \(Int($0.rounded()))" }
                        )
                    }
                    if let stress {
                        dayTile(
                            caption: "Stress",
                            value: "\(Int(stress.value.rounded()))",
                            unit: "/100",
                            note: stressCaption(stress.value)
                        )
                    }
                    if let band = targetBand {
                        dayTile(
                            caption: "Cible effort",
                            value: bandLabel(band),
                            unit: nil,
                            note: statusLabel(band.status)
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dayTile(caption: String, value: String, unit: String?, note: String?) -> some View {
        SharpitStatTile(caption: caption, value: value, unit: unit, note: note)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stressCaption(_ value: Double) -> String {
        if value >= 75 { return "Élevé" }
        if value >= 50 { return "Modéré" }
        return "Calme"
    }

    private func bandLabel(_ band: V1TodayTargetBand) -> String {
        let low = String(format: "%.0f", band.low)
        let high = String(format: "%.0f", band.high)
        return "\(low)–\(high)"
    }

    private func statusLabel(_ status: String?) -> String? {
        switch status {
        case "below": return "Sous la cible"
        case "within": return "Dans la cible"
        case "above": return "Au-dessus"
        default: return nil
        }
    }
}
