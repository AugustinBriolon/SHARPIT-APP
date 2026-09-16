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
    case me

    var title: String {
        switch self {
        case .plan: "Plan"
        case .coach: "Coach"
        case .activity: "Activité"
        case .me: "Moi"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: "calendar"
        case .coach: "bubble.left.and.bubble.right"
        case .activity: "figure.run"
        case .me: "person.crop.circle"
        }
    }

    /// Short horizon cue — shown once under the large mark.
    var horizonCue: String {
        switch self {
        case .plan: "7–14 j"
        case .coach: "Maintenant"
        case .activity: "Passé"
        case .me: "Toi"
        }
    }

    var surfaces: [ShellSurfaceMark] {
        switch self {
        case .plan:
            [
                ShellSurfaceMark(symbolName: "calendar.day.timeline.left", label: "Semaine"),
                ShellSurfaceMark(symbolName: "chart.line.uptrend.xyaxis", label: "Bilan"),
                ShellSurfaceMark(symbolName: "wand.and.stars", label: "Objectif"),
            ]
        case .coach:
            [
                ShellSurfaceMark(symbolName: "text.bubble", label: "Libre"),
                ShellSurfaceMark(symbolName: "link", label: "Contexte"),
                ShellSurfaceMark(symbolName: "brain.head.profile", label: "Mémoire"),
            ]
        case .activity:
            [
                ShellSurfaceMark(symbolName: "list.bullet.rectangle", label: "Historique"),
                ShellSurfaceMark(symbolName: "map", label: "Séjours"),
                ShellSurfaceMark(symbolName: "plus.circle", label: "Saisie"),
            ]
        case .me:
            [
                ShellSurfaceMark(symbolName: "figure.strengthtraining.traditional", label: "Corps"),
                ShellSurfaceMark(symbolName: "flag", label: "Objectifs"),
                ShellSurfaceMark(symbolName: "hand.raised", label: "Privé"),
            ]
        }
    }
}
