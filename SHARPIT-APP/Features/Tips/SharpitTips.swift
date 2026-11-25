import SwiftUI
import TipKit

/// The few gestures SharpIt has that nothing on screen shows, each said once, in place, and
/// dismissable (`docs/adr/0040`, the athlete's call, 2026-11-25). A visible button never gets a tip:
/// the layout explains it.
enum SharpitTips {
    /// At most one tip a day across the app, and each shown once.
    static func configure() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #if DEBUG
        // `-SharpitShowAllTips YES`: every tip at once, to look at them in the simulator.
        if UserDefaults.standard.bool(forKey: "SharpitShowAllTips") { Tips.showAllTipsForTesting() }
        #endif
        try? Tips.configure([.displayFrequency(.daily)])
    }
}

/// Résumé, the journal: a swipe sideways turns the day.
struct DaySwipeTip: Tip {
    static let dayOpened = Event(id: "day-opened")

    var title: Text { Text("Glisse pour changer de jour") }
    var message: Text? { Text("Vers la droite pour la veille, vers la gauche pour revenir.") }
    var image: Image? { Image(systemName: "hand.draw") }
    var rules: [Rule] { #Rule(Self.dayOpened) { $0.donations.count >= 3 } }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// Nutrition: a long press on a meal copies the day before's.
struct CopyMealTip: Tip {
    static let foodLogged = Event(id: "food-logged")

    var title: Text { Text("Mange souvent la même chose ?") }
    var message: Text? { Text("Appuie longuement sur un repas pour copier celui de la veille.") }
    var image: Image? { Image(systemName: "doc.on.doc") }
    var rules: [Rule] { #Rule(Self.foodLogged) { $0.donations.count >= 2 } }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// The exercise picker: a finger slid on the alphabet runs through the catalog.
struct ExerciseIndexTip: Tip {
    var title: Text { Text("Glisse sur l'alphabet") }
    var message: Text? { Text("Fais courir ton doigt sur les lettres pour parcourir le catalogue.") }
    var image: Image? { Image(systemName: "textformat.abc") }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// Objectifs: a long press on a goal marks it reached.
struct GoalReachedTip: Tip {
    static let goalsOpened = Event(id: "goals-opened")

    var title: Text { Text("Objectif atteint ?") }
    var message: Text? { Text("Appuie longuement sur un objectif en cours pour le valider.") }
    var image: Image? { Image(systemName: "flag") }
    var rules: [Rule] { #Rule(Self.goalsOpened) { $0.donations.count >= 2 } }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

extension View {
    /// A tip in Clinique's dress: the tile behind it, ink text, the glyph small and slate so it reads
    /// as a quiet mark beside the words rather than an illustration.
    func sharpitTipStyle() -> some View {
        tipBackground(SharpitColor.tile)
            .tint(SharpitColor.foreground)
            .tipImageStyle(SharpitColor.slate)
            .tipImageSize(CGSize(width: 22, height: 22))
    }
}
