import SwiftUI

enum ResumeScoreReadout {
    /// Days with an activity over the days of the window: Régularité's fallback, while the
    /// week's sessions are not read yet.
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

    /// Short enough for four columns on an iPhone.
    static func title(for key: V1TodaySignalKey) -> String {
        switch key {
        case .sleep: String(localized: "Sommeil")
        case .recovery: String(localized: "Récup.")
        case .effort, .adaptation, .stress: key.instrumentLabel
        }
    }

    /// The gauge's foot line, said to VoiceOver; the recovery one names the nervous system
    /// rather than « VFC ».
    static func caption(_ caption: String?, for key: V1TodaySignalKey) -> String? {
        guard let caption, !caption.isEmpty else { return nil }
        guard key == .recovery else { return caption }
        return caption
            .replacingOccurrences(of: "VFC", with: String(localized: "Système nerveux"))
            .replacingOccurrences(of: "vfc", with: String(localized: "Système nerveux"))
    }

    /// Calories eaten over the day's goal, as a ring: nil without a goal or a logged day.
    static func nutritionPercent(_ day: V1NutritionDay?) -> Int? {
        guard let pct = day?.goals?.calories.pct, pct.isFinite else { return nil }
        return Int(pct.rounded())
    }
}

/// Résumé's scores between two hairlines: one ring per overnight gauge, the day's nutrition,
/// then the week's regularity. A column opens the screen behind it when the row is given a way to.
struct ResumeScoreRow: View {
    let gauges: [OvernightGaugeModel]
    /// Calories over the day's goal, in percent; nil hides the ring's arc. `showsNutrition`
    /// false leaves the column out (the feature is off).
    var nutritionPercent: Int? = nil
    var showsNutrition = false
    /// The week's sessions, once read; until then Régularité falls back on the active days.
    var week: PlanWeekTotals? = nil
    var consistency: V1TodayConsistency? = nil
    var sleepOverrideCaption: String? = nil
    var pulseScores = false
    var animated = true
    var onSelect: ((V1TodaySignalKey) -> Void)? = nil
    var onOpenNutrition: (() -> Void)? = nil
    var onOpenRegularity: (() -> Void)? = nil

    var body: some View {
        CliniqueScoreStrip {
            ForEach(gauges) { gauge in
                column(action: onSelect.map { select in { select(gauge.key) } }) { gaugeColumn(gauge) }
            }
            if showsNutrition {
                column(action: onOpenNutrition) { nutritionColumn }
            }
            // Always in the row, an empty ring until the week is read: the row never grows a
            // column after it is drawn.
            column(action: onOpenRegularity) {
                CliniqueScoreColumn(
                    pillar: .coach, fraction: regularity?.fraction, title: String(localized: "Régularité"),
                    value: regularity?.value, scale: regularity?.scale, animated: animated
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(regularity?.spoken ?? String(localized: "Régularité, pas encore lue"))
            }
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
        return CliniqueScoreColumn(
            pillar: ResumeScoreReadout.pillar(for: gauge.key),
            fraction: fraction,
            title: title,
            value: fraction.map { "\(Int(($0 * 100).rounded()))" },
            scale: "100",
            isPulsing: pulseScores,
            animated: animated
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, String(localized: "\(gauge.score) sur 100"), caption].compactMap { $0 }.joined(separator: ", "))
    }

    private var nutritionColumn: some View {
        CliniqueScoreColumn(
            pillar: .nutrition,
            fraction: nutritionPercent.map { min(Double($0) / 100, 1) },
            title: String(localized: "Nutrition"),
            value: nutritionPercent.map { "\($0) %" },
            animated: animated
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            nutritionPercent.map { String(localized: "Nutrition, \($0) pour cent de l'objectif de calories") }
                ?? String(localized: "Nutrition, rien de noté")
        )
    }

    /// Sessions done over the week's, once Plan's count is read; the active days until then.
    private var regularity: (fraction: Double?, value: String, scale: String, spoken: String)? {
        if let week, week.totalSessions > 0 {
            return (
                week.sessionsFraction, "\(week.doneSessions)", "\(week.totalSessions)",
                String(localized: "Régularité, \(week.doneSessions) séances sur \(week.totalSessions) cette semaine")
            )
        }
        guard let consistency, !consistency.days.isEmpty else { return nil }
        let days = ResumeScoreReadout.activeDays(consistency)
        return (
            Double(days.done) / Double(days.of), "\(days.done)", "\(days.of)",
            String(localized: "Régularité, \(days.done) jours actifs sur \(days.of)")
        )
    }
}
