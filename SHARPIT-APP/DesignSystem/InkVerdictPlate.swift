import SwiftUI

/// The Today verdict — the one ink card on the morning screen, so it leads the page (ADR-085).
/// One idea per tier: the state and what changed since yesterday; the decision as the hero;
/// then why — the facts it was read from (freins, what held up). Confidence only
/// speaks when the reading is partial, and then says what is missing. Every colour comes from
/// the ink pair, so it holds on both appearances. Plain text only.
struct InkVerdictPlate: View {
    let plate: InkPlateModel
    var revealed: Bool = true
    var placeholder: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isExpertReading) private var isExpertReading

    private var reasons: [VerdictReason] { plate.reasons(isExpert: isExpertReading) }
    /// The server writes the explanation from the same signal codes as the reasons, so it only
    /// speaks when there are no facts to list — never the same thing twice.
    private var explanationText: String? {
        reasons.isEmpty ? plate.explanation(isExpert: isExpertReading) : nil
    }

    /// The decision the athlete reads first: headline when shown, otherwise the instruction.
    private var decisionText: String? {
        if plate.displaysHeadline { return plate.headline }
        return plate.safeInstruction
    }

    /// Secondary line under a shown headline — the concrete "what to do".
    private var decisionSubline: String? {
        guard plate.displaysHeadline else { return nil }
        return plate.safeInstruction
    }

    private var ink: Color { SharpitColor.inkSurfaceForeground }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            eyebrow

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
                        .foregroundStyle(ink.opacity(0.72))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !reasons.isEmpty || plate.estimationNote != nil {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    ForEach(reasons, id: \.self, content: reasonRow)
                    if let note = plate.estimationNote {
                        noteRow(note)
                    }
                }
            }
        }
        .contentTransition(.opacity)
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
        // A new verdict (ressenti saved, refresh) cross-fades in place — never a dip or a jump.
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: plate)
        .opacity(revealed ? 1 : 0)
        .scaleEffect(revealed || reduceMotion ? 1 : 0.97, anchor: .top)
        .offset(y: revealed || reduceMotion ? 0 : 8)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.40, dampingFraction: 1.0),
            value: revealed
        )
        .redacted(reason: placeholder ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The state, named once: glyph, label, and yesterday's state only when it changed.
    private var eyebrow: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Image(systemName: plate.stateCode?.symbolName ?? "circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SharpitColor.highlightForeground)
                .frame(width: 30, height: 30)
                .background(SharpitColor.highlight, in: Circle())
                .accessibilityHidden(true)
            Text(plate.statusLabel)
                .font(SharpitTypography.cardTitle)
                .tracking(SharpitTypography.cardTitleTracking)
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: SharpitSpacing.xs)
            if let yesterday = plate.yesterdayLabel {
                Text(yesterday)
                    .font(SharpitTypography.system(size: 13, weight: .medium, relativeTo: .footnote))
                    .foregroundStyle(ink.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private func reasonRow(_ reason: VerdictReason) -> some View {
        Label {
            Text(reason.label)
                .foregroundStyle(ink.opacity(reason.isSupport ? 0.72 : 0.92))
        } icon: {
            Image(systemName: reason.isSupport ? "checkmark" : "arrow.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(reason.isSupport ? SharpitColor.inkAccent : ink.opacity(0.6))
                .frame(width: 16)
        }
        .font(SharpitTypography.system(size: 15, weight: .medium, relativeTo: .subheadline))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func noteRow(_ note: String) -> some View {
        Label {
            Text(note)
        } icon: {
            Image(systemName: "info.circle").frame(width: 16)
        }
        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
        .foregroundStyle(ink.opacity(0.55))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
    }

    private var accessibilityLabel: String {
        let freins = reasons.filter { !$0.isSupport }.map(\.label)
        let supports = reasons.filter(\.isSupport).map(\.label)
        return [
            plate.statusLabel,
            decisionText,
            decisionSubline,
            plate.yesterdayLabel,
            explanationText,
            freins.isEmpty ? nil : String(localized: "Freins : \(freins.joined(separator: ", "))"),
            supports.isEmpty ? nil : String(localized: "Porté par : \(supports.joined(separator: ", "))"),
            plate.estimationNote,
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
            stateCode: .recover,
            supportSignals: [.subjectiveOk],
            yesterdayLabel: String(localized: "Hier : Prudence")
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
            stateCode: .recover,
            supportSignals: [.subjectiveOk],
            yesterdayLabel: String(localized: "Hier : Prudence")
        )
    )
    .padding()
    .background(SharpitCanvasBackground())
    .preferredColorScheme(.dark)
}
