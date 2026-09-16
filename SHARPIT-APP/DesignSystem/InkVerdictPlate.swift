import SwiftUI

enum SharpitInk {
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.09)
    static let foreground = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.55)
    static let highlight = Color(red: 0.83, green: 1.0, blue: 0.20)
    static let caution = Color.orange
}

struct InkVerdictPlate: View {
    let plate: InkPlateModel
    var revealed: Bool = true
    var placeholder: Bool = false

    private var tone: PackTierTone { PackTierTone.dot(for: plate.packTier) }
    private var filledBars: Int { ConfidenceBars.filled(fromPct: plate.confidencePct) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            statusRow
            Text(plate.headline)
                .font(SharpitTypography.verdict())
                .tracking(SharpitTypography.verdictTracking)
                .foregroundStyle(SharpitInk.foreground)
                .lineSpacing(2)
            if let action = plate.actionLine, !action.isEmpty {
                Text(action)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SharpitInk.foreground.opacity(0.82))
            }
            if let cause = plate.limitingCause, !cause.isEmpty {
                Text("Limité par · \(cause)")
                    .font(SharpitTypography.label())
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitInk.muted)
            }
            if plate.confidenceLabel != nil || plate.confidencePct != nil {
                confidenceRow
            }
            if !plate.estimationGaps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plate.estimationGaps, id: \.self) { gap in
                        Text("· \(gap)")
                            .font(.caption2)
                            .foregroundStyle(SharpitInk.muted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .background(SharpitInk.surface, in: RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 12)
        .redacted(reason: placeholder ? .placeholder : [])
        .accessibilityElement(children: .combine)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
            Text(plate.statusLabel)
                .font(SharpitTypography.label())
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitInk.muted)
            Spacer(minLength: 0)
        }
    }

    private var confidenceRow: some View {
        HStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...3, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(barColor.opacity(level <= filledBars ? 0.9 : 0.25))
                        .frame(width: 6, height: CGFloat(6 + level * 4))
                }
            }
            .accessibilityHidden(true)
            if let label = plate.confidenceLabel {
                Text(label)
                    .font(SharpitTypography.label())
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitInk.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var dotColor: Color {
        switch tone {
        case .highlight: SharpitInk.highlight
        case .caution: SharpitInk.caution
        case .muted: SharpitInk.foreground.opacity(0.4)
        }
    }

    private var barColor: Color { dotColor }
}

#Preview {
    InkVerdictPlate(
        plate: InkPlateModel(
            statusLabel: "FEU VERT",
            headline: "Journée modérée",
            actionLine: "Entraîne-toi — légèrement",
            limitingCause: "Sommeil",
            confidencePct: 55,
            confidenceLabel: "ESTIMATION PARTIELLE",
            packTier: .partial,
            estimationGaps: ["Baseline HRV partielle (moins de 14 j)"],
            posture: .steady
        )
    )
    .padding()
}
