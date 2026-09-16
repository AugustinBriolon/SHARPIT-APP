import SwiftUI

struct VerdictHero: View {
    let verdict: V1TodayVerdict

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(verdict.eyebrow)
            Text(verdict.headline)
                .font(SharpitTypography.verdict())
                .tracking(SharpitTypography.verdictTracking)
                .lineSpacing(2)
            Text(verdict.subline)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.82))
            HStack(spacing: SharpitSpacing.md) {
                if let cause = verdict.limitingCause {
                    Label(cause, systemImage: "target")
                }
                if let confidence = verdict.confidencePct {
                    HStack(spacing: 4) {
                        Text("\(confidence)%")
                            .font(.body.monospacedDigit().weight(.semibold))
                        Text("confiance")
                            .font(.body)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, SharpitSpacing.xxs)
        .padding(.bottom, 4)
    }
}
