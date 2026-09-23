import SwiftUI

/// The Today verdict plate — the first and largest thing on the morning screen.
///
/// It is the web's ink band: `surface-ink`, which is Forest on light and Lime on dark, so
/// the verdict is the one inverted surface in the app. No gradient, no drop shadow — the
/// plate separates itself from the canvas by inversion, which is the strongest available
/// separation and the one the web already uses.
struct InkVerdictPlate: View {
    let plate: InkPlateModel
    var revealed: Bool = true
    var placeholder: Bool = false

    /// Drives the 2-beat status dot pulse that fires once the plate is fully revealed.
    @State private var dotPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var statusTone: PackTierTone { PackTierTone.statusDot(for: plate.statusLabel) }
    private var barsTone: PackTierTone { PackTierTone.bars(for: plate.packTier) }
    private var filledBars: Int { ConfidenceBars.filled(fromPct: plate.confidencePct) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            statusRow

            Text(plate.headline)
                .font(SharpitTypography.verdict)
                .tracking(SharpitTypography.verdictTracking)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)

            if let action = plate.actionLine, !action.isEmpty {
                Text(action)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.82))
            }

            if let cause = plate.limitingCause, !cause.isEmpty {
                Text("Limité par · \(cause)")
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(mutedInk)
            }

            if plate.confidenceLabel != nil || plate.confidencePct != nil {
                confidenceRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.ink)
        // Spring scale-up reveal: plate arrives with physical weight.
        .opacity(revealed ? 1 : 0)
        .scaleEffect(revealed ? 1 : 0.94, anchor: .top)
        .offset(y: revealed ? 0 : 10)
        .animation(
            reduceMotion ? .easeOut(duration: 0.01)
                : .spring(response: 0.38, dampingFraction: 0.78),
            value: revealed
        )
        .redacted(reason: placeholder ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onChange(of: revealed) { _, isRevealed in
            guard isRevealed, !reduceMotion else { return }
            // Fire dot pulse after the plate spring settles (~400 ms).
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeInOut(duration: 0.22)) { dotPulse = true }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeInOut(duration: 0.22)) { dotPulse = false }
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.easeInOut(duration: 0.22)) { dotPulse = true }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeInOut(duration: 0.22)) { dotPulse = false }
            }
        }
    }

    /// The plate reads the estimation gaps aloud even though it no longer prints them:
    /// honesty about limits is a product feature, a five-bullet list under a verdict is
    /// not. The list belongs to a drill-down, not to the first thing seen in the morning.
    private var accessibilityLabel: String {
        [
            plate.statusLabel,
            plate.headline,
            plate.actionLine,
            plate.limitingCause.map { "Limité par \($0)" },
            plate.confidenceLabel,
            plate.estimationGaps.isEmpty ? nil : plate.estimationGaps.joined(separator: ", "),
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ". ")
    }

    /// Secondary text on the ink band: the band's own foreground, held back.
    private var mutedInk: Color {
        SharpitColor.inkSurfaceForeground.opacity(0.62)
    }

    private var statusRow: some View {
        HStack(spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    // 2-beat pulse fires once the plate spring settles.
                    .scaleEffect(dotPulse ? 1.35 : 1.0)
                Text(plate.statusLabel)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(mutedInk)
            }
            .padding(.horizontal, SharpitSpacing.sm)
            .padding(.vertical, SharpitSpacing.xxs + 2)
            .background(dotColor.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)
        }
    }

    private var confidenceRow: some View {
        HStack(spacing: SharpitSpacing.xs) {
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
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(mutedInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, SharpitSpacing.xxs)
    }

    private var dotColor: Color { inkColor(for: statusTone) }
    private var barColor: Color { inkColor(for: barsTone) }

    /// Tones resolved *on the ink band*, where `--ink-accent` is the legible accent:
    /// Lime on Forest in light mode, Forest on Lime in dark.
    private func inkColor(for tone: PackTierTone) -> Color {
        switch tone {
        case .highlight: SharpitColor.inkAccent
        case .caution: SharpitColor.signalCaution
        case .muted: SharpitColor.inkSurfaceForeground.opacity(0.4)
        }
    }
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
    .background(SharpitCanvasBackground())
}
