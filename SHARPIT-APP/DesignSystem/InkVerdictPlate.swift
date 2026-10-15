import SwiftUI

/// The Today verdict plate — the first and largest thing on the morning screen.
///
/// Ink band (`surface-ink`): Forest on light, Lime on dark. Separation by inversion only.
/// Every color on this surface must come from the ink pair (`inkSurfaceForeground` /
/// `inkAccent`) — canvas tokens like `primary` collide with the inverted band in dark mode.
///
/// Layout: status + symbol → decision → why. Plain text only — never Markdown.
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

    /// Ink-legible ink: cream on Forest, Forest on Lime.
    private var ink: Color { SharpitColor.inkSurfaceForeground }
    /// Accent that inverts with the band — never canvas `primary`.
    private var accent: Color { SharpitColor.inkAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            headerRow

            if let decision = decisionText {
                Text(decision)
                    .font(SharpitTypography.verdict)
                    .tracking(SharpitTypography.verdictTracking)
                    .foregroundStyle(ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let subline = decisionSubline {
                Text(subline)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(ink.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let explanation = explanationText {
                Text(explanation)
                    .font(SharpitTypography.body)
                    .foregroundStyle(ink.opacity(0.78))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var headerRow: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(plate.statusLabel)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(accent)

                if let vs = plate.vsYesterdayLabel, !vs.isEmpty {
                    Text(vs)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(ink.opacity(0.72))
                }
            }

            Spacer(minLength: 0)

            Image(systemName: plate.stateCode?.symbolName ?? "circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
        }
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
