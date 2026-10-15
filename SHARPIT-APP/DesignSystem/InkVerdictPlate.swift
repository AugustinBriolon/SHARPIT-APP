import SwiftUI

/// The Today verdict plate — the first and largest thing on the morning screen.
///
/// Ink band (`surface-ink`): Forest on light, Lime on dark. Separation by inversion only —
/// no nested surfaces, no chip chrome. Hierarchy is type + one hierarchical SF Symbol,
/// the same language as Fitness / Health status cards.
///
/// Layout: status meta + symbol → decision (verdict type) → why (body) → quiet frein/confidence.
/// Plain text only — never Markdown.
struct InkVerdictPlate: View {
    let plate: InkPlateModel
    var revealed: Bool = true
    var placeholder: Bool = false
    /// Bumped when a wellness save changed the verdict — drives a one-shot fade.
    var contentFadeToken: Int = 0

    @State private var symbolPulse = false
    @State private var contentOpacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isExpertReading) private var isExpertReading

    private var statusTone: PackTierTone {
        PackTierTone.statusDot(for: plate.statusLabel, stateCode: plate.stateCode)
    }
    private var barsTone: PackTierTone { PackTierTone.bars(for: plate.packTier) }
    private var filledBars: Int { ConfidenceBars.filled(fromPct: plate.confidencePct) }

    private var accent: Color {
        plate.stateCode?.inkAccent ?? inkColor(for: statusTone)
    }

    private var explanationText: String? { plate.explanation(isExpert: isExpertReading) }
    private var instructionText: String? { plate.safeInstruction }
    private var limiterChip: String? { plate.limiterChip(isExpert: isExpertReading) }

    private var legacyLimiter: String? {
        guard limiterChip == nil,
              let cause = plate.limitingCause, !cause.isEmpty,
              explanationText == nil, instructionText == nil
        else { return nil }
        return "Limité par · \(cause)"
    }

    private var freinLine: String? { limiterChip ?? legacyLimiter }

    private var showsConfidence: Bool {
        plate.confidenceLabel != nil || plate.confidencePct != nil
    }

    /// The decision the athlete reads first: headline when shown, otherwise the instruction.
    private var decisionText: String? {
        if plate.displaysHeadline { return plate.headline }
        return instructionText
    }

    /// Secondary line under a shown headline — the concrete "what to do".
    private var decisionSubline: String? {
        guard plate.displaysHeadline else { return nil }
        return instructionText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            headerRow

            if let decision = decisionText {
                Text(decision)
                    .font(SharpitTypography.verdict)
                    .tracking(SharpitTypography.verdictTracking)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let subline = decisionSubline {
                Text(subline)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let explanation = explanationText {
                Text(explanation)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.62))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if freinLine != nil || showsConfidence {
                metaFooter
            }
        }
        .opacity(contentOpacity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SharpitSpacing.md)
        .padding(.vertical, SharpitSpacing.lg)
        .sharpitSurface(.ink)
        .opacity(revealed ? 1 : 0)
        .scaleEffect(revealed ? 1 : 0.96, anchor: .top)
        .offset(y: revealed ? 0 : 8)
        .animation(
            reduceMotion ? .easeOut(duration: 0.01)
                : .spring(response: 0.40, dampingFraction: 1.0),
            value: revealed
        )
        .redacted(reason: placeholder ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onChange(of: revealed) { _, isRevealed in
            guard isRevealed, !reduceMotion else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.easeInOut(duration: 0.22)) { symbolPulse = true }
                try? await Task.sleep(for: .milliseconds(280))
                withAnimation(.easeInOut(duration: 0.22)) { symbolPulse = false }
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

    /// Decision first — the plate's job is "what to do this morning".
    private var accessibilityLabel: String {
        [
            decisionText,
            decisionSubline,
            plate.statusLabel,
            plate.vsYesterdayLabel,
            explanationText,
            freinLine,
            plate.confidenceLabel,
            plate.estimationGaps.isEmpty ? nil : plate.estimationGaps.joined(separator: ", "),
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ". ")
    }

    private var mutedInk: Color {
        SharpitColor.inkSurfaceForeground.opacity(0.52)
    }

    /// Eyebrow + vs-yesterday on the left; one hierarchical symbol as the only ornament.
    private var headerRow: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(plate.statusLabel)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(accent.opacity(0.9))

                if let vs = plate.vsYesterdayLabel, !vs.isEmpty {
                    Text(vs)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(mutedInk)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: plate.stateCode?.symbolName ?? "circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .scaleEffect(symbolPulse ? 1.06 : 1.0)
                .accessibilityHidden(true)
        }
    }

    /// One quiet line — no capsules, no nested panels.
    private var metaFooter: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            if let frein = freinLine {
                Text(frein)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if showsConfidence {
                confidenceMarks
            }
        }
        .padding(.top, SharpitSpacing.xxs)
    }

    private var confidenceMarks: some View {
        HStack(spacing: SharpitSpacing.xs) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(1...3, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(inkColor(for: barsTone).opacity(level <= filledBars ? 0.7 : 0.16))
                        .frame(width: 4, height: CGFloat(4 + level * 3))
                }
            }
            .accessibilityHidden(true)
            if let label = plate.confidenceLabel {
                Text(label)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(mutedInk)
            }
        }
    }

    private func inkColor(for tone: PackTierTone) -> Color {
        switch tone {
        case .highlight: SharpitColor.inkAccent
        case .caution: SharpitColor.signalCaution
        case .muted: SharpitColor.inkSurfaceForeground.opacity(0.4)
        }
    }
}

#Preview("Repos · sans headline") {
    InkVerdictPlate(
        plate: InkPlateModel(
            statusLabel: "Repos",
            headline: "Priorité au repos",
            actionLine: "Privilégie le repos ou une marche très légère.",
            limitingCause: nil,
            confidencePct: 55,
            confidenceLabel: "Estimation partielle",
            packTier: .partial,
            estimationGaps: ["Baseline HRV partielle (moins de 14 j)"],
            posture: .protect,
            explanationEssential: "Ta forme ressentie est bonne, mais ton corps n’a pas encore récupéré et ta nuit a été trop courte. Un vrai repos aujourd’hui.",
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

#Preview("Feu vert · avec headline") {
    InkVerdictPlate(
        plate: InkPlateModel(
            statusLabel: "FEU VERT",
            headline: "Séance prévue pour aujourd'hui",
            actionLine: "Entraîne-toi — légèrement",
            limitingCause: nil,
            confidencePct: 72,
            confidenceLabel: "Estimation partielle",
            packTier: .partial,
            estimationGaps: [],
            posture: .steady,
            explanationEssential: "La nuit a tenu. Tu peux tenir le plan sans forcer.",
            explanationExpert: "HRV dans la norme.",
            instruction: "Entraîne-toi — légèrement",
            limiterSignals: [],
            vsYesterdayLabel: "Comme hier",
            showHeadline: true,
            stateCode: .trainSmart
        )
    )
    .padding()
    .background(SharpitCanvasBackground())
}
