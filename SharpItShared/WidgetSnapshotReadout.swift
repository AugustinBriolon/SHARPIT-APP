import CoreGraphics
import Foundation

/// How the widgets read a section — pure, shared so the rules are tested with the app.
extension WidgetSnapshot.Nutrition {
    /// Eaten against the day's budget, 0…100 for the dial.
    var dialScore: CGFloat? {
        guard let calories, let calorieGoal, calorieGoal > 0 else { return nil }
        return CGFloat(min(calories / calorieGoal, 1) * 100)
    }

    /// The figure inside the dial: what is left, or how far past.
    var dialFigure: String {
        guard let remaining else { return SharpitFigureFormat.kcal(calories) }
        return SharpitFigureFormat.kcal(abs(remaining))
    }

    var dialCaption: String {
        guard let remaining else { return "kcal aujourd'hui" }
        return remaining >= 0 ? "kcal restantes" : "kcal au-delà"
    }

    var hasLog: Bool { (calories ?? 0) > 0 }
}

extension WidgetSnapshot.Weight {
    var change: Double? { previousKilograms.map { kilograms - $0 } }

    /// Whether the change went towards the target; nil without one.
    var movesTowardsTarget: Bool? {
        guard let targetKilograms, let change, abs(change) >= 0.05 else { return nil }
        return (targetKilograms - kilograms).magnitude < (targetKilograms - (kilograms - change)).magnitude
    }

    var changeLine: String? {
        guard let change else { return nil }
        let window = changeWindowDays.map { " · \($0) j" } ?? ""
        return SharpitFigureFormat.kilogramChange(change) + window
    }

    var targetLine: String? {
        guard let targetKilograms else { return nil }
        let left = targetKilograms - kilograms
        if abs(left) < 0.05 { return "Objectif \(SharpitFigureFormat.target(targetKilograms)) atteint" }
        return "Encore \(SharpitFigureFormat.kilograms(abs(left))) kg · objectif \(SharpitFigureFormat.target(targetKilograms))"
    }
}

