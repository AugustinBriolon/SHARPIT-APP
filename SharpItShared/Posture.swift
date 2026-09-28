import SwiftUI

/// The day's posture: how hard today can go. Shared with the widgets, which color the verdict
/// the app's way.
nonisolated enum V1TodayPosture: String, Codable, Sendable {
    case protect
    case steady
    case push
    case uncertain

    /// Mapped onto the web's semantic signal tokens. `design.md`: colour is emotional state, and
    /// `RECOVER` uses protective sage — never punitive red. So `protect` takes caution amber,
    /// not `signalRisk`.
    var tone: Color {
        switch self {
        case .protect: SharpitColor.signalCaution
        case .steady: SharpitColor.primary
        case .push: SharpitColor.signalRecovery
        case .uncertain: SharpitColor.signalNeutral
        }
    }

    var symbolName: String {
        switch self {
        case .protect: "shield.lefthalf.filled"
        case .steady: "equal.circle"
        case .push: "arrow.up.circle"
        case .uncertain: "questionmark.circle"
        }
    }
}
