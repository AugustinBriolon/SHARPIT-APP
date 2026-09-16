import SwiftUI

struct SessionPlate: View {
    let session: V1TodaySession

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                    if let subtitle = session.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(session.kind == .done ? "Faite" : "Prévue")
                    .font(SharpitTypography.eyebrow())
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            if !session.metrics.isEmpty {
                HStack(spacing: SharpitSpacing.md) {
                    ForEach(session.metrics, id: \.label) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(metric.value)
                                    .font(SharpitTypography.data())
                                Text(metric.unit)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text(metric.label)
                                .font(SharpitTypography.label())
                                .tracking(SharpitTypography.labelTracking)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitGlassCard()
    }
}
