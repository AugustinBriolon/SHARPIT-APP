import SwiftUI

struct SharpitCanvasBackground: View {
    let posture: V1TodayPosture?

    var body: some View {
        LinearGradient(
            colors: [
                SharpitPostureStyle.canvasTop(for: posture),
                Color(.systemBackground),
            ],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
}
