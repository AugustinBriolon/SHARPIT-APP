import Foundation

/// Résumé's four rings as the « Résumé » widget draws them: last night, the recovery, the day's
/// food against its goal, the week's active days — each only what the app already wrote.
nonisolated struct WidgetResumeRing: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable { case sleep, recovery, nutrition, regularity }

    let kind: Kind
    /// 0…1, or nil while the figure is not known: the ring then shows its track alone.
    let fraction: Double?
    /// « 86 », « 77 % », « 4/7 »; « — » while unknown.
    let value: String

    var id: Kind { kind }

    /// The rings of a day, in Résumé's order; a feature the athlete hides leaves its ring out.
    static func rings(
        day: WidgetSnapshot.Day?,
        nutrition: WidgetSnapshot.Nutrition?,
        regularity: WidgetSnapshot.Regularity?,
        features: V1FeaturePrefs
    ) -> [WidgetResumeRing] {
        var rings = [
            score(.sleep, day?.sleep?.score),
            score(.recovery, day?.recovery?.score),
        ]
        if features.isOn(.nutrition) {
            if let calories = nutrition?.calories, let goal = nutrition?.calorieGoal, goal > 0 {
                let share = calories / goal
                rings.append(WidgetResumeRing(kind: .nutrition, fraction: min(max(share, 0), 1), value: "\(Int((share * 100).rounded())) %"))
            } else {
                rings.append(WidgetResumeRing(kind: .nutrition, fraction: nil, value: "—"))
            }
        }
        if features.isOn(.regularity) {
            let days = regularity?.days ?? []
            if days.isEmpty {
                rings.append(WidgetResumeRing(kind: .regularity, fraction: nil, value: "—"))
            } else {
                let done = days.filter(\.hasActivity).count
                rings.append(WidgetResumeRing(kind: .regularity, fraction: Double(done) / Double(days.count), value: "\(done)/\(days.count)"))
            }
        }
        return rings
    }

    private static func score(_ kind: Kind, _ score: Int?) -> WidgetResumeRing {
        guard let score else { return WidgetResumeRing(kind: kind, fraction: nil, value: "—") }
        return WidgetResumeRing(kind: kind, fraction: min(max(Double(score) / 100, 0), 1), value: "\(score)")
    }
}
