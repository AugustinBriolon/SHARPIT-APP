import SwiftUI

/// The page canvas — Snow White on light, Forest Night on dark.
///
/// It is flat on purpose. The previous canvas carried a posture-tinted gradient and two
/// radial halos; `design.md` forbids decorative washes without informational function,
/// and the tint belongs to the verdict plate, which is the thing whose state it describes.
struct SharpitCanvasBackground: View {
    var body: some View {
        SharpitColor.background.ignoresSafeArea()
    }
}
