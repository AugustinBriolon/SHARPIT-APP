import SwiftUI

/// The Today verdict plate — the first and largest thing on the morning screen.
///
/// It is the web's ink band: `surface-ink`, which is Forest on light and Lime on dark, so
/// the verdict is the one inverted surface in the app. No gradient, no drop shadow — the
/// plate separates itself from the canvas by inversion, which is the strongest available
/// separation and the one the web already uses.
///
/// Layout (PR #154): tag (+ vsYesterday on the right) → optional headline → explanation
/// (density-aware, secondary) → instruction (bold). Plain text only — never Markdown.
struct InkVerdictPlate: View {
    let plate: InkPlateModel
    var revealed: Bool = true
    var placeholder: Bool = false
    /// Bumped when a wellness save changed the verdict — drives a one-shot fade.
    var contentFadeToken: Int = 0

    /// Drives the 2-beat status dot pulse that fires once the plate is fully revealed.
    @State private var dotPulse = false
    @State private var contentOpacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isExpertReading) private var isExpertReading

    private var statusTone: PackTierTone {
        PackTierTone.statusDot(for: plate.statusLabel, stateCode: plate.stateCode)
    }
    private var barsTone: PackTierTone { PackTierTone.bars(for: plate.packTier) }
    private var filledBars: Int { ConfidenceBars.filled(fromPct: plate.confidencePct) }

    private var tagAccent: Color {
        plate.stateCode?.inkAccent ?? inkColor(for: statusTone)
    }

    private var explanationText: String? { plate.explanation(isExpert: isExpertReading) }
    private var instructionText: String? { plate.safeInstruction }
    private var limiterChip: String? { plate.limiterChip(isExpert: isExpertReading) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            statusRow

            if plate.displaysHeadline {
                Text(plate.headline)
                    .font(SharpitTypography.verdict)
                    .tracking(SharpitTypography.verdictTracking)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let explanation = explanationText {
                Text(explanation)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let instruction = instructionText {
                Text(instruction)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let chip = limiterChip {
                Text(chip)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let cause = plate.limitingCause, !cause.isEmpty,
                      explanationText == nil, instructionText == nil
            {
                // Legacy fallback when the additive frein codes are absent.
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
        .opacity(contentOpacity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.ink)
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
        .onChange(of: contentFadeToken) { _, _ in
            guard contentFadeToken > 0 else { return }
            if reduceMotion {
                contentOpacity = 1
                return
            }
            contentOpacity = 0.35
            withAnimation(.easeInOut(duration: 0.28)) {
                contentOpacity = 1
            }
        }
    }

    /// The plate reads the estimation gaps aloud even though it no longer prints them:
    /// honesty about limits is a product feature, a five-bullet list under a verdict is
    /// not. The list belongs to a drill-down, not to the first thing seen in the morning.
    private var accessibilityLabel: String {
        [
            plate.statusLabel,
            plate.vsYesterdayLabel,
            plate.displaysHeadline ? plate.headline : nil,
            explanationText,
            instructionText,
            limiterChip,
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
        HStack(alignment: .center, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                if let code = plate.stateCode {
                    Image(systemName: code.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tagAccent)
                        .accessibilityHidden(true)
                } else {
                    Circle()
                        .fill(tagAccent)
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotPulse ? 1.35 : 1.0)
                }
                Text(plate.statusLabel)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(mutedInk)
            }
            .padding(.horizontal, SharpitSpacing.sm)
            .padding(.vertical, SharpitSpacing.xxs + 2)
            .background(tagAccent.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)

            if let vs = plate.vsYesterdayLabel, !vs.isEmpty {
                Text(vs)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(mutedInk)
                    .multilineTextAlignment(.trailing)
            }
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
            statusLabel: "Repos",
            headline: "Priorité au repos",
            actionLine: "Privilégie le repos ou une marche très légère.",
            limitingCause: nil,
            confidencePct: 55,
            confidenceLabel: "ESTIMATION PARTIELLE",
            packTier: .partial,
            estimationGaps: ["Baseline HRV partielle (moins de 14 j)"],
            posture: .protect,
            explanationEssential: "Ton corps n’a pas encore récupéré.",
            explanationExpert: "VFC basse.",
            instruction: "Privilégie le repos ou une marche très légère.",
            limiterSignals: [.hrvLow, .sleepShort],
            vsYesterdayLabel: "Changé depuis hier",
            showHeadline: false,
            stateCode: .recover
        )
    )
    .padding()
    .background(SharpitCanvasBackground())
}
