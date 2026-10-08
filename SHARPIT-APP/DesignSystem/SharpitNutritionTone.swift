import SwiftUI

/// Nutrition's hues, kept apart from the macros' (protein, carbohydrates and fat already take the
/// signal family): a meal is told by the time of day it belongs to, an action of the add sheet by
/// what it does — as Activité tells a sport and Paramètres a setting by theirs.
enum SharpitNutritionTone {
    /// Petit-déjeuner amber, déjeuner coral, dîner indigo, collations rose — keyed by the stored
    /// meal name (`breakfast`), which imported meals and the coach's flags also carry.
    static func meal(_ storedName: String) -> Color {
        switch storedName.lowercased() {
        case "breakfast": Color(red: 0.91, green: 0.55, blue: 0.05)
        case "lunch": Color(red: 0.92, green: 0.40, blue: 0.26)
        case "dinner": Color(red: 0.39, green: 0.40, blue: 0.85)
        case "snacks", "snack": Color(red: 0.86, green: 0.33, blue: 0.55)
        default: SharpitColor.primary
        }
    }

    /// A meal's glyph or « + » drawn in its hue, lifted on dark so it stays legible on the canvas.
    static func mealLabel(_ storedName: String) -> Color {
        SharpitElevatedColor.adaptive(light: meal(storedName), dark: meal(storedName), darkLift: 0.35)
    }

    /// The add sheet's ways in, each on its own tile.
    enum Action {
        static let scan = Color(red: 0.12, green: 0.62, blue: 0.56)
        static let describe = Color(red: 0.45, green: 0.38, blue: 0.88)
        static let ownFoods = Color(red: 0.92, green: 0.52, blue: 0.20)
        static let quickAdd = Color(red: 0.55, green: 0.36, blue: 0.86)
        static let create = Color(red: 0.34, green: 0.44, blue: 0.86)
        static let savedMeals = Color(red: 0.86, green: 0.36, blue: 0.42)
        static let recipe = Color(red: 0.30, green: 0.62, blue: 0.30)
    }
}
