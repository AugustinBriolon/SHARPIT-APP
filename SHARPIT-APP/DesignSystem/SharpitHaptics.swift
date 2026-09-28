import UIKit

/// Haptics keep one generator per kind and re-prepare it after each use. A generator
/// created on the tap wakes the Taptic Engine on demand, so the pulse lands a beat after
/// the visual change it is meant to confirm.
enum SharpitHaptics {
    enum Kind {
        case soft
        case light
        case success
        /// A notch passed on a ruler or a dial: short and crisp, one per unit.
        case tick
    }

    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)

    /// Warms the tick up before a gesture, so the first notch is not late.
    static func prepareTick() {
        rigidImpact.prepare()
    }

    static func play(_ kind: Kind) {
        switch kind {
        case .soft:
            softImpact.impactOccurred()
            softImpact.prepare()
        case .light:
            lightImpact.impactOccurred()
            lightImpact.prepare()
        case .success:
            notification.notificationOccurred(.success)
            notification.prepare()
        case .tick:
            // The selection generator is too faint for a notch felt under a sliding finger.
            rigidImpact.impactOccurred(intensity: 0.7)
            rigidImpact.prepare()
        }
    }
}
