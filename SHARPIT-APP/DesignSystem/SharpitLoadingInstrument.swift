import SwiftUI

/// Résumé's shape while the day is read: the verdict, the scores and a session, greyed.
struct SharpitLoadingInstrument: View {
    /// Whether the day will carry a nutrition ring, so the row loads with the columns it keeps.
    var showsNutrition = true

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                // « Lecture de ta nuit »: the verdict's place, said as being read rather than greyed.
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Lecture de ta nuit")
                            .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                            .foregroundStyle(SharpitColor.slate)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 28)
                    .overlay(Capsule().strokeBorder(SharpitColor.divider, lineWidth: 1))
                    ForEach([0.62, 0.78, 0.54], id: \.self) { share in
                        Capsule().fill(SharpitColor.tile)
                            .frame(height: share == 0.62 ? 22 : 14)
                            .containerRelativeFrame(.horizontal) { width, _ in width * share }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, SharpitSpacing.lg)
                .padding(.bottom, 24)
                // Empty rings: track only, « Pas encore » — the arcs fill when the day arrives.
                ResumeScoreRow(gauges: OvernightGaugeModel.placeholders, showsNutrition: showsNutrition)
                SessionPlate(session: .placeholder, showPriorityTag: false)
                    .redacted(reason: .placeholder)
                    .padding(.horizontal, SharpitSpacing.lg)
                    .padding(.top, SharpitSpacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, SharpitSpacing.lg)
            .cliniqueRisingSheet(wash: .neutral)
        }
        .modifier(ScrollUnderGlass())
        .cliniqueBackdropPage()
        .allowsHitTesting(false)
        .accessibilityLabel("Chargement du résumé")
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
