import SwiftUI

/// Résumé's shape while the day is read: the verdict, the scores and a session, greyed.
struct SharpitLoadingInstrument: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                VerdictHero(plate: .placeholder, placeholder: true)
                // Empty rings: track only, « Pas encore » — the arcs fill when the day arrives.
                ResumeScoreRow(gauges: OvernightGaugeModel.placeholders)
                SessionPlate(session: .placeholder, showPriorityTag: false)
                    .redacted(reason: .placeholder)
                    .padding(.horizontal, SharpitSpacing.lg)
                    .padding(.top, SharpitSpacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
        .cliniqueSheet(wash: .neutral)
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
    /// No score yet: each ring draws its track and « Pas encore ».
    static var placeholders: [OvernightGaugeModel] {
        [
            OvernightGaugeModel(key: .sleep, score: "—", caption: nil),
            OvernightGaugeModel(key: .recovery, score: "—", caption: nil),
        ]
    }
}
