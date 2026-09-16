import SwiftUI
import UIKit

struct SharpitCanvasBackground: View {
    var posture: V1TodayPosture? = nil

    var body: some View {
        LinearGradient(
            colors: [
                SharpitCanvas.washTop(for: posture),
                SharpitCanvas.washMid,
                Color(.systemBackground),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

enum SharpitCanvas {
    /// Soft mint wash shared across every shell screen.
    static let washMid = Color(red: 0.82, green: 0.92, blue: 0.86)

    static func washTop(for posture: V1TodayPosture?) -> Color {
        let tint = posture.map(SharpitPostureStyle.color(for:)) ?? SharpitInk.highlight
        return tint.opacity(0.28).mix(with: washMid, amount: 0.55)
    }
}

private extension Color {
    /// Cheap perceptual blend toward another color (sRGB approx).
    func mix(with other: Color, amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        let a = UIColor(self)
        let b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            opacity: aa + (ba - aa) * t
        )
    }
}
