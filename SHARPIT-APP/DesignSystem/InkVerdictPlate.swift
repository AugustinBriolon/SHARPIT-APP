import SwiftUI

/// The Today verdict — the one ink card on the morning screen, so it leads the page (ADR-085).
/// Laid out as the reference stat card turned over: a lime tile with the state's glyph,
/// « Verdict du jour » and what changed, the status as a lime pill; then the decision as the
/// hero, the why in softened white, and the confidence as a lime bar on graphite.
/// Every colour comes from the ink pair, so it holds on both appearances. Plain text only.
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

    private var ink: Color { SharpitColor.inkSurfaceForeground }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            header

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                if let decision = decisionText {
                    Text(decision)
                        .font(SharpitTypography.system(size: 28, weight: .bold, relativeTo: .title))
                        .tracking(-0.5)
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subline = decisionSubline {
                    Text(subline)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let explanation = explanationText {
                    Text(explanation)
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(ink.opacity(0.7))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            if let confidence = plate.confidencePct {
                confidenceBar(confidence)
            }
        }
        .opacity(contentOpacity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
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

    private var header: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Image(systemName: plate.stateCode?.symbolName ?? "circle.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(SharpitColor.highlightForeground)
                .frame(width: SharpitTokens.tileSize, height: SharpitTokens.tileSize)
                .sharpitConcentricBackground(SharpitColor.highlight, minimum: SharpitRadius.tile)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Verdict du jour")
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(ink)
                if let vs = plate.vsYesterdayLabel, !vs.isEmpty {
                    Text(vs)
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(ink.opacity(0.6))
                }
            }
            .lineLimit(1)
            Spacer(minLength: SharpitSpacing.xs)
            if !plate.statusLabel.isEmpty {
                SharpitPill(plate.statusLabel, style: .lime)
            }
        }
    }

    private func confidenceBar(_ confidence: Int) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(plate.confidenceLabel ?? String(localized: "Confiance"))
                    .foregroundStyle(ink.opacity(0.6))
                Spacer(minLength: SharpitSpacing.xs)
                Text("\(confidence) %")
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(ink)
            }
            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.14))
                    Capsule()
                        .fill(SharpitColor.highlight)
                        .frame(width: proxy.size.width * SharpitProgressMath.clamped(Double(confidence) / 100))
                }
            }
            .frame(height: 6)
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
            statusLabel: String(localized: "Repos"),
            headline: String(localized: "Priorité au repos"),
            actionLine: String(localized: "Privilégie le repos ou une marche très légère."),
            limitingCause: nil,
            confidencePct: 55,
            confidenceLabel: String(localized: "Estimation partielle"),
            packTier: .partial,
            estimationGaps: [String(localized: "Baseline HRV partielle (moins de 14 j)")],
            posture: .protect,
            explanationEssential: String(localized: "Ta forme ressentie est bonne, mais ton corps n’a pas encore récupéré et ta nuit a été trop courte. Un vrai repos aujourd’hui."),
            explanationExpert: String(localized: "VFC basse."),
            instruction: String(localized: "Privilégie le repos ou une marche très légère."),
            limiterSignals: [.hrvLow, .sleepShort],
            vsYesterdayLabel: String(localized: "Changé depuis hier"),
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
            statusLabel: String(localized: "Repos"),
            headline: String(localized: "Priorité au repos"),
            actionLine: String(localized: "Privilégie le repos ou une marche très légère."),
            limitingCause: nil,
            confidencePct: 55,
            confidenceLabel: String(localized: "Estimation partielle"),
            packTier: .partial,
            estimationGaps: [],
            posture: .protect,
            explanationEssential: String(localized: "Ta forme ressentie est bonne, mais ton corps n’a pas encore récupéré et ta nuit a été trop courte. Un vrai repos aujourd’hui."),
            explanationExpert: String(localized: "VFC basse."),
            instruction: String(localized: "Privilégie le repos ou une marche très légère."),
            limiterSignals: [.hrvLow, .sleepShort],
            vsYesterdayLabel: String(localized: "Changé depuis hier"),
            showHeadline: false,
            stateCode: .recover
        )
    )
    .padding()
    .background(SharpitCanvasBackground())
    .preferredColorScheme(.dark)
}
