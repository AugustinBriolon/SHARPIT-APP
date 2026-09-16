import SwiftUI

struct SignalStrip: View {
    let signals: [V1TodaySignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SharpitEyebrow("Signaux")
            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(signals) { signal in
                    VStack(spacing: 6) {
                        Text(signal.score)
                            .font(SharpitTypography.data())
                        Text(signal.key.instrumentLabel)
                            .font(SharpitTypography.label())
                            .tracking(SharpitTypography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SharpitSpacing.xs)
                    .sharpitGlassCard()
                }
            }
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
}
