import Foundation

struct ShellSurfaceMark: Equatable, Sendable, Identifiable {
    var id: String { symbolName + label }
    let symbolName: String
    let label: String
}

enum ShellDestination: String, CaseIterable, Sendable {
    case plan
    case coach
    case activity
    case body

    var title: String {
        switch self {
        case .plan: String(localized: "Plan")
        case .coach: String(localized: "Coach")
        case .activity: String(localized: "Activité")
        case .body: String(localized: "Santé")
        }
    }

    var systemImage: String {
        switch self {
        case .plan: "calendar"
        case .coach: "bubble.left.and.bubble.right"
        case .activity: "figure.run"
        case .body: "heart"
        }
    }

    /// Short horizon cue — shown once under the large mark.
    var horizonCue: String {
        switch self {
        case .plan: "7–14 j"
        case .coach: String(localized: "Maintenant")
        case .activity: String(localized: "Passé")
        case .body: String(localized: "Toi")
        }
    }

    var surfaces: [ShellSurfaceMark] {
        switch self {
        case .plan:
            [
                ShellSurfaceMark(symbolName: "calendar.day.timeline.left", label: String(localized: "Semaine")),
                ShellSurfaceMark(symbolName: "chart.line.uptrend.xyaxis", label: String(localized: "Bilan")),
                ShellSurfaceMark(symbolName: "wand.and.stars", label: String(localized: "Objectif")),
            ]
        case .coach:
            [
                ShellSurfaceMark(symbolName: "text.bubble", label: String(localized: "Libre")),
                ShellSurfaceMark(symbolName: "link", label: String(localized: "Contexte")),
                ShellSurfaceMark(symbolName: "brain.head.profile", label: String(localized: "Mémoire")),
            ]
        case .activity:
            [
                ShellSurfaceMark(symbolName: "list.bullet.rectangle", label: String(localized: "Historique")),
                ShellSurfaceMark(symbolName: "map", label: String(localized: "Séjours")),
                ShellSurfaceMark(symbolName: "plus.circle", label: String(localized: "Saisie")),
            ]
        case .body:
            [
                ShellSurfaceMark(symbolName: "heart", label: String(localized: "Signes vitaux")),
                ShellSurfaceMark(symbolName: "scalemass", label: String(localized: "Corps")),
                ShellSurfaceMark(symbolName: "figure.walk", label: String(localized: "Au quotidien")),
            ]
        }
    }
}
