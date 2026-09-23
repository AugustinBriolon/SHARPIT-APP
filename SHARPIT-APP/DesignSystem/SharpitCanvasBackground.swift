import SwiftUI

/// The page canvas — Snow White on light, Forest Night on dark — with a subtle dot-grid
/// texture and two soft brand halos for depth.
///
/// The texture follows the same rule as the previous flat canvas: no posture-tinted colour
/// wash with informational function. The dot grid and halos are pure material — they give
/// the screen a sense of physical surface without encoding any data state.
struct SharpitCanvasBackground: View {
    @Environment(\.sharpitElevation) private var elevation

    var body: some View {
        ZStack {
            // Base flat colour — same as before.
            switch elevation {
            case .base: SharpitColor.background.ignoresSafeArea()
            case .sheet: SharpitElevatedColor.sheet.ignoresSafeArea()
            }

            // Texture layer: only on the main canvas, not inside sheets.
            if elevation == .base {
                SharpitCanvasTexture()
                    .ignoresSafeArea()
            }
        }
    }
}
