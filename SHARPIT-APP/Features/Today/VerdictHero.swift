import SwiftUI

/// How Résumé's verdict reads in Clinique terms (`docs/adr/0035`).
enum VerdictReadout {
    /// The verdict's status, from the tone its state code carries.
    static func status(for plate: InkPlateModel) -> CliniqueStatus {
        switch PackTierTone.statusDot(for: plate.statusLabel, stateCode: plate.stateCode) {
        case .highlight: .good
        case .caution: .watch
        case .muted: .unknown
        }
    }

    /// The wash the sheet takes under that verdict.
    static func wash(for status: CliniqueStatus) -> CliniqueWash {
        switch status {
        case .good: .good
        case .watch: .watch
        case .alert: .alert
        case .unknown, .protect, .pro: .neutral
        }
    }
}

/// The Today verdict at the head of the sheet, on its wash. One idea per tier: the state as a
/// status pill, and yesterday's when it changed; the decision as the headline; then why — the
/// facts it was read from (freins, what held up). Confidence only speaks when the reading is
/// partial, and then says what is missing. Plain text only.
struct VerdictHero: View {
    let plate: InkPlateModel
    var revealed: Bool = true

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

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: SharpitSpacing.xxs) {
                CliniqueStatusPill(plate.statusLabel, status: VerdictReadout.status(for: plate))
                if let yesterday = plate.yesterdayLabel {
                    Text(yesterday)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(1)
                }
            }
            if let decision = decisionText {
                Text(decision)
                    .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2))
                    .tracking(-0.5)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let subline = decisionSubline {
                secondary(subline)
            }
            if let explanation = explanationText {
                secondary(explanation)
            }
            if !reasons.isEmpty {
                // The facts the verdict was read from, as one line under it.
                secondary(reasons.map(\.label).joined(separator: " · "))
            }
            if let note = plate.estimationNote {
                Text(note)
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SharpitSpacing.lg)
        .padding(.top, SharpitSpacing.lg)
        .padding(.bottom, 20)
        // A new verdict (ressenti saved, refresh) cross-fades in place — never a dip or a jump.
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: plate)
        .arrived(revealed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
            .foregroundStyle(SharpitColor.slate)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
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
