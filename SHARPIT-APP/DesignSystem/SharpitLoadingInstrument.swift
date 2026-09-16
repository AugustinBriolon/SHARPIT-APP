import SwiftUI

struct SharpitLoadingInstrument: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                InkVerdictPlate(plate: .placeholder, placeholder: true)
                SessionPlate(session: .placeholder)
                OvernightGaugePair(gauges: OvernightGaugeModel.placeholders)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Chargement du résumé")
    }
}

private extension InkPlateModel {
    static var placeholder: InkPlateModel {
        InkPlateModel(
            statusLabel: "FEU VERT",
            headline: "Séance prévue pour aujourd'hui",
            actionLine: "Tenir le plan sans forcer",
            limitingCause: "Sommeil court",
            confidencePct: 72,
            confidenceLabel: "ESTIMATION PARTIELLE",
            packTier: .partial,
            estimationGaps: ["Baseline"],
            posture: .steady
        )
    }
}

private extension SessionCardModel {
    static var placeholder: SessionCardModel {
        SessionCardModel(
            id: "skeleton",
            kind: .planned,
            title: "Seuil 40 min",
            subtitle: nil,
            metrics: [V1TodayMetric(label: "Durée", value: "40", unit: "min")],
            sport: "Course",
            priority: true
        )
    }
}

private extension OvernightGaugeModel {
    static var placeholders: [OvernightGaugeModel] {
        [
            OvernightGaugeModel(key: .sleep, score: "88", caption: nil),
            OvernightGaugeModel(key: .recovery, score: "88", caption: nil),
        ]
    }
}
