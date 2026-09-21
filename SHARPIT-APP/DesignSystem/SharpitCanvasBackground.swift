import SwiftUI

/// The page canvas — Snow White on light, Forest Night on dark. Inside a sheet it takes
/// the sheet's raised tone, so a screen pushed or embedded there never shows black.
///
/// It is flat on purpose. The previous canvas carried a posture-tinted gradient and two
/// radial halos; `design.md` forbids decorative washes without informational function,
/// and the tint belongs to the verdict plate, which is the thing whose state it describes.
struct SharpitCanvasBackground: View {
    @Environment(\.sharpitElevation) private var elevation

    var body: some View {
        switch elevation {
        case .base: SharpitColor.background.ignoresSafeArea()
        case .sheet: SharpitElevatedColor.sheet.ignoresSafeArea()
        }
    }
}
