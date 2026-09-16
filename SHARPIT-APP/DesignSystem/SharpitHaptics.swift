import UIKit

enum SharpitHaptics {
    enum Kind {
        case soft
        case light
        case success
    }

    static func play(_ kind: Kind) {
        switch kind {
        case .soft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
