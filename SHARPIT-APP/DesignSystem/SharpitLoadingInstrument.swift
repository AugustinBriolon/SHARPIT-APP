import SwiftUI

struct SharpitLoadingInstrument: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                InkVerdictPlate(plate: .placeholder, placeholder: true)
                VStack(alignment: .leading, spacing: 10) {
                    SharpitEyebrow("Séance")
                    SessionPlate(session: .placeholder, showPriorityTag: false)
                }
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
            packTier: .full,
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
            metrics: [
                V1TodayMetric(label: "Intensité", value: "Endurance", unit: ""),
                V1TodayMetric(label: "Durée", value: "40", unit: "min"),
                V1TodayMetric(label: "Charge", value: "50", unit: "TSS"),
            ],
            sport: "Course",
            priority: true
        )
    }
}

private extension OvernightGaugeModel {
    static var placeholders: [OvernightGaugeModel] {
        [
            OvernightGaugeModel(key: .sleep, score: "66", caption: "Nuit dernière"),
            OvernightGaugeModel(key: .recovery, score: "55", caption: "Frein · sommeil"),
        ]
    }
}
