import SwiftUI

struct SharpitLoadingInstrument: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                Group {
                    InkVerdictPlate(plate: .placeholder, placeholder: true)
                    SessionPlate(session: .placeholder, showPriorityTag: false)
                }
                .redacted(reason: .placeholder)

                // Live empty gauges: tip at 0, score at 0 — fill animates on load.
                OvernightGaugePair(gauges: OvernightGaugeModel.placeholders)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
        .allowsHitTesting(false)
        .accessibilityLabel("Chargement du résumé")
    }
}

private extension InkPlateModel {
    static var placeholder: InkPlateModel {
        InkPlateModel(
            statusLabel: "FEU VERT",
            headline: String(localized: "Séance prévue pour aujourd'hui"),
            actionLine: String(localized: "Tenir le plan sans forcer"),
            limitingCause: String(localized: "Sommeil court"),
            confidencePct: 72,
            confidenceLabel: "ESTIMATION PARTIELLE",
            packTier: .full,
            estimationGaps: [String(localized: "Baseline")],
            posture: .steady
        )
    }
}

extension SessionCardModel {
    static var placeholder: SessionCardModel {
        SessionCardModel(
            id: "skeleton",
            kind: .planned,
            title: String(localized: "Seuil 40 min"),
            subtitle: nil,
            metrics: [
                V1TodayMetric(label: String(localized: "Intensité"), value: String(localized: "Endurance"), unit: ""),
                V1TodayMetric(label: String(localized: "Durée"), value: "40", unit: "min"),
                V1TodayMetric(label: String(localized: "Charge"), value: "50", unit: "TSS"),
            ],
            sport: String(localized: "Course"),
            priority: true
        )
    }
}

extension OvernightGaugeModel {
    static var placeholders: [OvernightGaugeModel] {
        [
            OvernightGaugeModel(key: .sleep, score: "0", caption: String(localized: "Nuit dernière")),
            OvernightGaugeModel(key: .recovery, score: "0", caption: String(localized: "Frein · sommeil")),
        ]
    }
}
