import SwiftUI

extension SharpitColor {
    /// The app icon's green (`SharpIt.icon`): light at the top, deeper at the foot. The web's
    /// `brand-icon.ts` carries the same two stops.
    static let brandMarkGradient = LinearGradient(
        colors: [
            Color(red: 149 / 255, green: 255 / 255, blue: 178 / 255),
            Color(red: 55 / 255, green: 244 / 255, blue: 134 / 255),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// The app icon's mark — six dots on a hexagon, as `SharpIt.icon` draws it — breathing while
/// something is read before a screen can be drawn (the gate, the wizard's first read).
struct SharpitLaunchMark: View {
    var body: some View {
        Image(systemName: "circle.hexagonpath.fill")
            .font(.system(size: 40, weight: .regular))
            .foregroundStyle(SharpitColor.brandMarkGradient)
            .symbolEffect(.breathe, isActive: !SharpitMotion.reduceMotion)
            .accessibilityLabel("Chargement")
    }
}
