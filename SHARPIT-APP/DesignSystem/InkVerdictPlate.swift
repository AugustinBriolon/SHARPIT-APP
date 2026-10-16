import SwiftUI

/// The Today verdict — the first card on the morning screen, laid out as the reference stat
/// card (ADR-085): the state's tile, « Verdict du jour » and what changed, the status as a lime
/// pill; then the decision as the hero, the why in muted prose, and the confidence as a bar.
/// Plain text only — never Markdown.
struct InkVerdictPlate: View {
    let plate: InkPlateModel
    var revealed: Bool = true
    var placeholder: Bool = false
    /// Bumped when a wellness save changed the verdict — drives a one-shot fade.
    var contentFadeToken: Int = 0

    @State private var contentOpacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isExpertReading) private var isExpertReading

    private var explanationText: String? { plate.explanation(isExpert: isExpertReading) }
    private var instructionText: String? { plate.safeInstruction }

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
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(
                title: "Verdict du jour",
                symbol: plate.stateCode?.symbolName ?? "circle.fill",
                subtitle: plate.vsYesterdayLabel,
                showsChevron: false
            ) {
                if !plate.statusLabel.isEmpty {
                    SharpitPill(plate.statusLabel, style: .lime)
                }
            }

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                if let decision = decisionText {
                    Text(decision)
                        .font(SharpitTypography.system(size: 26, weight: .bold, relativeTo: .title))
                        .tracking(-0.4)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subline = decisionSubline {
                    Text(subline)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let explanation = explanationText {
                    Text(explanation)
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            if let confidence = plate.confidencePct {
                SharpitProgressBar(
                    label: plate.confidenceLabel ?? "Confiance",
                    value: "\(confidence) %",
                    fraction: Double(confidence) / 100
                )
            }
        }
        .opacity(contentOpacity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
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

    private var accessibilityLabel: String {
        [
            decisionText,
            decisionSubline,
            plate.statusLabel,
            plate.vsYesterdayLabel,
            explanationText,
            plate.estimationGaps.isEmpty ? nil : plate.estimationGaps.joined(separator: ", "),
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ". ")
    }

}

#Preview("Repos · light") {
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
    .preferredColorScheme(.light)
}

#Preview("Repos · dark") {
    InkVerdictPlate(
        plate: InkPlateModel(
            statusLabel: "Repos",
            headline: "Priorité au repos",
            actionLine: "Privilégie le repos ou une marche très légère.",
            limitingCause: nil,
            confidencePct: 55,
            confidenceLabel: "Estimation partielle",
            packTier: .partial,
            estimationGaps: [],
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
    .preferredColorScheme(.dark)
}
