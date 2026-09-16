import SwiftUI

struct SignalStrip: View {
    let signals: [V1TodaySignal]
    var revealed: Bool = true
    var pulseScores: Bool = false

    var body: some View {
        HStack(spacing: SharpitSpacing.xxs) {
            ForEach(Array(signals.enumerated()), id: \.element.id) { index, signal in
                SignalCell(signal: signal, pulse: pulseScores)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 8)
                    .animation(
                        SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: index)),
                        value: revealed
                    )
            }
        }
    }
}

struct SignalCell: View {
    let signal: V1TodaySignal
    var pulse: Bool = false

    private var fraction: Double? {
        AnimatedScoreText.progressFraction(from: signal.score)
    }

    var body: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Image(systemName: signal.key.instrumentSymbol)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            AnimatedScoreText(score: signal.score)
                .opacity(pulse ? 0.55 : 1)
            SignalTrack(fraction: fraction)
            Text(signal.key.instrumentLabel)
                .font(SharpitTypography.label())
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SharpitSpacing.xs)
        .padding(.horizontal, 4)
        .sharpitGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.key.instrumentLabel), \(signal.score)")
    }
}

struct SignalTrack: View {
    let fraction: Double?

    @State private var fill: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                if let fraction {
                    Capsule()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: max(geo.size.width * fill, fraction > 0 ? 2 : 0))
                }
            }
        }
        .frame(height: 3)
        .onAppear { animate(to: fraction.map { CGFloat($0) } ?? 0) }
        .onChange(of: fraction) { _, newValue in
            animate(to: newValue.map { CGFloat($0) } ?? 0)
        }
    }

    private func animate(to value: CGFloat) {
        if SharpitMotion.reduceMotion || reduceMotion {
            fill = value
            return
        }
        SharpitMotion.run(.easeOut(duration: SharpitMotion.countUpDuration)) {
            fill = value
        }
    }
}

extension V1TodaySignalKey {
    var instrumentLabel: String {
        switch self {
        case .sleep: "Nuit"
        case .recovery: "Récup"
        case .effort: "Effort"
        case .adaptation: "Adapt."
        }
    }

    var instrumentSymbol: String {
        switch self {
        case .sleep: "moon.zzz"
        case .recovery: "heart"
        case .effort: "bolt"
        case .adaptation: "arrow.triangle.2.circlepath"
        }
    }
}
