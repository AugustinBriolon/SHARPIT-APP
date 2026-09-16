import SwiftUI

struct VerdictHero: View {
    let verdict: V1TodayVerdict
    var revealed: Bool = true
    var pulseScores: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                SharpitEyebrow(verdict.eyebrow)
                Spacer(minLength: 0)
                Image(systemName: verdict.posture.instrumentSymbol)
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(SharpitPostureStyle.color(for: verdict.posture))
                    .accessibilityLabel(verdict.posture.rawValue)
            }
            Text(verdict.headline)
                .font(SharpitTypography.verdict())
                .tracking(SharpitTypography.verdictTracking)
                .lineSpacing(2)
            if !verdict.subline.isEmpty {
                Text(verdict.subline)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if let confidence = verdict.confidencePct {
                ConfidenceRing(
                    percent: confidence,
                    posture: verdict.posture,
                    pulse: pulseScores
                )
            }
            if let cause = verdict.limitingCause {
                Label(cause, systemImage: "target")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, SharpitSpacing.xxs)
        .padding(.bottom, 4)
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 12)
        .accessibilityElement(children: .combine)
    }
}

struct ConfidenceRing: View {
    let percent: Int
    let posture: V1TodayPosture
    var pulse: Bool = false

    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var target: CGFloat {
        min(max(CGFloat(percent) / 100, 0), 1)
    }

    var body: some View {
        HStack(spacing: SharpitSpacing.xs) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        SharpitPostureStyle.color(for: posture),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(percent)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            .frame(width: 36, height: 36)
            Text("Confiance")
                .font(SharpitTypography.label())
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .opacity(pulse ? 0.55 : 1)
        .onAppear { animate(to: target) }
        .onChange(of: percent) { _, _ in animate(to: target) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Confiance \(percent) pour cent")
    }

    private func animate(to value: CGFloat) {
        if SharpitMotion.reduceMotion || reduceMotion {
            progress = value
            return
        }
        SharpitMotion.run(.easeOut(duration: SharpitMotion.countUpDuration)) {
            progress = value
        }
    }
}

private extension V1TodayPosture {
    var instrumentSymbol: String {
        switch self {
        case .protect: "shield.lefthalf.filled"
        case .steady: "equal.circle"
        case .push: "arrow.up.circle"
        case .uncertain: "questionmark.circle"
        }
    }
}
