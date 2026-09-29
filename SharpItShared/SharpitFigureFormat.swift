import Foundation

/// Figures as the app writes them, French-grouped: shared with the widgets so a kilocalorie or a
/// kilogram reads the same on the home screen as in the app.
nonisolated enum SharpitFigureFormat {
    private static let french = Locale(identifier: "fr_FR")

    /// `2 140` — whole kilocalories.
    static func kcal(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Int(value.rounded()).formatted(.number.locale(french))
    }

    /// What the remaining calories say: left to eat, or past the goal.
    static func remainingKcal(_ remaining: Double?) -> String? {
        guard let remaining else { return nil }
        let rounded = Int(remaining.rounded())
        if rounded >= 0 { return "Reste \(kcal(Double(rounded))) kcal" }
        return "\(kcal(Double(-rounded))) kcal au-delà"
    }

    /// `72,4` — one decimal.
    static func kilograms(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(french))
    }

    /// `70 kg`, `68,5 kg` — a target: no trailing `,0`.
    static func target(_ value: Double) -> String {
        let whole = value.rounded() == value
        return (whole ? Int(value).formatted(.number.locale(french)) : kilograms(value)) + " kg"
    }

    /// `−0,6 kg` — a change, signed, a true minus.
    static func kilogramChange(_ delta: Double) -> String {
        let magnitude = kilograms(abs(delta))
        if abs(delta) < 0.05 { return "stable" }
        return "\(delta < 0 ? "−" : "+")\(magnitude) kg"
    }

    /// `32,4` — kilometres, one decimal below a hundred, whole above.
    static func kilometers(_ value: Double) -> String {
        value >= 100
            ? Int(value.rounded()).formatted(.number.locale(french))
            : value.formatted(.number.precision(.fractionLength(1)).locale(french))
    }

    /// `3 h 10`, `45 min` — a length of time.
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        guard total >= 60 else { return "\(total) min" }
        let rest = total % 60
        return rest == 0 ? "\(total / 60) h" : "\(total / 60) h \(String(format: "%02d", rest))"
    }
}
