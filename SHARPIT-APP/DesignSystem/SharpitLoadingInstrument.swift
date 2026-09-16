import SwiftUI

struct SharpitLoadingInstrument: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                verdictSkeleton
                signalsSkeleton
                sessionSkeleton
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Chargement du résumé")
    }

    private var verdictSkeleton: some View {
        VerdictHero(
            verdict: V1TodayVerdict(
                eyebrow: "Ce matin",
                headline: "Séance prévue pour aujourd'hui",
                subline: "Tenir le plan sans forcer",
                posture: .steady,
                confidencePct: 72,
                limitingCause: "Sommeil court"
            )
        )
    }

    private var sessionSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            SharpitEyebrow("Séance")
            SessionPlate(
                session: V1TodaySession(
                    id: "skeleton",
                    kind: .planned,
                    title: "Seuil 40 min",
                    subtitle: "Course",
                    metrics: [V1TodayMetric(label: "Durée", value: "40", unit: "min")]
                )
            )
        }
    }

    private var signalsSkeleton: some View {
        SignalStrip(
            signals: [
                V1TodaySignal(key: .sleep, score: "88", caption: nil),
                V1TodaySignal(key: .recovery, score: "88", caption: nil),
                V1TodaySignal(key: .effort, score: "88", caption: nil),
                V1TodaySignal(key: .adaptation, score: "88", caption: nil),
            ]
        )
    }
}
