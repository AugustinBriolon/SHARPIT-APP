import SwiftUI

/// The page canvas — flat cool off-white on light, near-black on dark (ADR-085).
/// No texture, no halo: the white cards are the only depth.
struct SharpitCanvasBackground: View {
    @Environment(\.sharpitElevation) private var elevation

    var body: some View {
        switch elevation {
        case .base: SharpitColor.background.ignoresSafeArea()
        case .sheet: SharpitElevatedColor.sheet.ignoresSafeArea()
        }
    }
}
