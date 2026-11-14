import SwiftUI

enum ResumeScoreReadout {
    /// Days with an activity over the days of the week shown: what the ring of Régularité fills to.
    static func activeDays(_ consistency: V1TodayConsistency) -> (done: Int, of: Int) {
        (consistency.days.filter(\.hasActivity).count, consistency.days.count)
    }

    static func pillar(for key: V1TodaySignalKey) -> CliniquePillar {
        switch key {
        case .sleep: .sleep
        case .recovery: .recovery
        case .effort, .adaptation, .stress: .coach
        }
    }

    static func title(for key: V1TodaySignalKey) -> String {
        switch key {
        case .sleep: String(localized: "Sommeil")
        case .recovery: String(localized: "Récupération")
        case .effort, .adaptation, .stress: key.instrumentLabel
        }
    }

    /// The gauge's foot line; the recovery one names the nervous system rather than « VFC ».
    static func caption(_ caption: String?, for key: V1TodaySignalKey) -> String? {
        guard let caption, !caption.isEmpty else { return nil }
        guard key == .recovery else { return caption }
        return caption
            .replacingOccurrences(of: "VFC", with: String(localized: "Système nerveux"))
            .replacingOccurrences(of: "vfc", with: String(localized: "Système nerveux"))
    }
}

/// Résumé's scores between two hairlines: one ring per overnight gauge, then the week's
/// regularity. A column opens the screen behind it when the row is given a way to.
struct ResumeScoreRow: View {
    let gauges: [OvernightGaugeModel]
    var consistency: V1TodayConsistency? = nil
    var sleepOverrideCaption: String? = nil
    var pulseScores = false
    var animated = true
    var onSelect: ((V1TodaySignalKey) -> Void)? = nil
    var onOpenRegularity: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            HStack(alignment: .top, spacing: 0) {
                ForEach(gauges) { gauge in
                    column(action: onSelect.map { select in { select(gauge.key) } }) {
                        gaugeColumn(gauge)
                    }
                }
                if let consistency, !consistency.days.isEmpty {
                    column(action: onOpenRegularity) { regularityColumn(consistency) }
                }
            }
            .padding(.vertical, 18)
            CliniqueDivider()
        }
    }

    @ViewBuilder
    private func column(action: (() -> Void)?, @ViewBuilder content: () -> some View) -> some View {
        if let action {
            Button(action: action) { content().contentShape(.rect) }
                .buttonStyle(.sharpitPressable)
        } else {
            content()
        }
    }

    private func gaugeColumn(_ gauge: OvernightGaugeModel) -> some View {
        let fraction = AnimatedScoreText.progressFraction(from: gauge.score)
        let title = ResumeScoreReadout.title(for: gauge.key)
        let caption = ResumeScoreReadout.caption(
            gauge.key == .sleep ? (sleepOverrideCaption ?? gauge.caption) : gauge.caption,
            for: gauge.key
        )
        return ScoreColumn(
            pillar: ResumeScoreReadout.pillar(for: gauge.key),
            fraction: fraction,
            title: title,
            value: fraction.map { "\(Int(($0 * 100).rounded()))" },
            scale: "100",
            caption: caption,
            pulse: pulseScores,
            animated: animated
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, String(localized: "\(gauge.score) sur 100"), caption].compactMap { $0 }.joined(separator: ", "))
    }

    private func regularityColumn(_ consistency: V1TodayConsistency) -> some View {
        let days = ResumeScoreReadout.activeDays(consistency)
        return ScoreColumn(
            pillar: .coach,
            fraction: Double(days.done) / Double(days.of),
            title: String(localized: "Régularité"),
            value: "\(days.done)",
            scale: "\(days.of)",
            caption: String(localized: "jours actifs"),
            pulse: false,
            animated: animated
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Régularité, \(days.done) jours actifs sur \(days.of)"))
    }
}

private struct ScoreColumn: View {
    let pillar: CliniquePillar
    let fraction: Double?
    let title: String
    let value: String?
    let scale: String
    let caption: String?
    let pulse: Bool
    let animated: Bool

    var body: some View {
        VStack(spacing: 6) {
            CliniqueRing(pillar: pillar, fraction: fraction, animated: animated)
                .padding(.bottom, 2)
            Text(title)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let value {
                (Text(value)
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    + Text(" / \(scale)").font(SharpitTypography.meta).foregroundStyle(SharpitColor.slate))
                    .opacity(pulse ? 0.55 : 1)
            } else {
                Text("Pas encore")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            if let caption {
                Text(caption)
                    .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(SharpitColor.slate)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, SharpitSpacing.xxs)
        .frame(maxWidth: .infinity)
    }
}
