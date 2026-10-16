import SwiftUI

/// Nutrition's tones: ink since ADR-085, as a sport is — a meal or an add action is told by its
/// glyph and name. Kept as one place so a hue cannot creep back per screen.
enum SharpitNutritionTone {
    /// Monochrome since ADR-085: a meal is told by its glyph and name, never by a hue.
    static func meal(_ storedName: String) -> Color {
        SharpitColor.primary
    }

    /// A meal's glyph or « + » drawn in its hue, lifted on dark so it stays legible on the canvas.
    static func mealLabel(_ storedName: String) -> Color {
        SharpitElevatedColor.adaptive(light: meal(storedName), dark: meal(storedName), darkLift: 0.35)
    }

    /// The add sheet's ways in, each on its own tile.
    enum Action {
        static let scan = SharpitColor.primary
        static let describe = SharpitColor.primary
        static let ownFoods = SharpitColor.primary
        static let quickAdd = SharpitColor.primary
        static let create = SharpitColor.primary
        static let savedMeals = SharpitColor.primary
        static let recipe = SharpitColor.primary
    }
}
